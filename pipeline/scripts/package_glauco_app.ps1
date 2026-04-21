[CmdletBinding()]
param(
    [string]$ScriptPath = "bin/main.rb",

    [string]$AppName = "glauco-app",

    [string]$Version = "1.0.0",

    [string]$OutputDir = "dist",

    [string[]]$PackageTypes = @("app-image"),

    [string[]]$ExtraModules = @(),

    [string[]]$JavaOptions = @(
        "--enable-native-access=ALL-UNNAMED",
        "-Dfile.encoding=UTF-8"
    ),

    [string]$Vendor = "Glauco",

    [string]$IconPath,

    [switch]$SkipJar,

    [switch]$SkipJlink,

    [switch]$SkipJpackage,

    [switch]$KeepWorkDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Resolve-ProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-UserPath {
    param(
        [string]$PathValue,
        [string]$BasePath
    )

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return (Resolve-Path $PathValue).Path
    }

    return (Resolve-Path (Join-Path $BasePath $PathValue)).Path
}

function Get-Slug {
    param([string]$Value)

    $slug = $Value.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
    $slug = $slug.Trim("-")

    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Nao foi possivel gerar um identificador para o app."
    }

    return $slug
}

function Normalize-RelativePath {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    $baseUri = New-Object System.Uri(((Resolve-Path $BasePath).Path.TrimEnd("\") + "\"))
    $targetUri = New-Object System.Uri((Resolve-Path $TargetPath).Path)
    $relative = $baseUri.MakeRelativeUri($targetUri).ToString()
    return [System.Uri]::UnescapeDataString($relative)
}

function Get-JavaHome {
    if ($env:JAVA_HOME) {
        $jpackageFromEnv = Join-Path $env:JAVA_HOME "bin\jpackage.exe"
        if (Test-Path $jpackageFromEnv) {
            return (Resolve-Path $env:JAVA_HOME).Path
        }
    }

    $javaOutput = & java -XshowSettings:properties -version 2>&1
    $javaHomeLine = $javaOutput | Where-Object { $_ -match "^\s*java\.home = " } | Select-Object -First 1

    if (-not $javaHomeLine) {
        throw "Nao foi possivel descobrir o JAVA_HOME. Defina a variavel JAVA_HOME."
    }

    $javaHome = ($javaHomeLine -split "=", 2)[1].Trim()
    $jpackagePath = Join-Path $javaHome "bin\jpackage.exe"

    if (-not (Test-Path $jpackagePath)) {
        throw "O JAVA_HOME encontrado nao possui jpackage: $javaHome"
    }

    return (Resolve-Path $javaHome).Path
}

function Resolve-ToolPath {
    param(
        [string]$ToolName,
        [string]$JavaHome
    )

    if ($JavaHome) {
        $javaTool = Join-Path $JavaHome "bin\$ToolName.exe"
        if (Test-Path $javaTool) {
            return (Resolve-Path $javaTool).Path
        }
    }

    $command = Get-Command $ToolName -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    throw "Ferramenta '$ToolName' nao encontrada."
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory
    )

    Write-Host ("   " + $FilePath + " " + ($Arguments -join " "))

    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Comando falhou com codigo $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function New-CleanDirectory {
    param([string]$Path)

    if (Test-Path $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }

    New-Item -ItemType Directory -Path $Path | Out-Null
}

function Get-ModuleList {
    param(
        [string]$JdepsPath,
        [string]$JarPath,
        [string[]]$ExtraModules
    )

    $defaults = @(
        "java.base",
        "java.datatransfer",
        "java.desktop",
        "java.logging",
        "java.prefs",
        "java.xml",
        "jdk.unsupported"
    )

    $detected = @()

    try {
        $raw = & $JdepsPath --ignore-missing-deps --recursive --print-module-deps $JarPath 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $detected = ($raw -join "") -split "," | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        }
    }
    catch {
        $detected = @()
    }

    return @($defaults + $detected + $ExtraModules | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
}

$projectRoot = Resolve-ProjectRoot
$scriptFullPath = Resolve-UserPath -PathValue $ScriptPath -BasePath $projectRoot

if (-not $scriptFullPath.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "O script precisa estar dentro do projeto: $projectRoot"
}

$scriptRelativePath = Normalize-RelativePath -BasePath $projectRoot -TargetPath $scriptFullPath
$scriptDirectoryRelativePath = Split-Path $scriptRelativePath -Parent
$displayName = if ($AppName) { $AppName } else { [System.IO.Path]::GetFileNameWithoutExtension($scriptFullPath) }
$appId = Get-Slug $displayName

$outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
}
else {
    Join-Path $projectRoot $OutputDir
}
$workRoot = Join-Path $projectRoot "build\packaging\$appId"
$jarOutputPath = Join-Path $outputRoot "$appId.jar"
$runtimeOutputPath = Join-Path $outputRoot "$appId-runtime"
$warblerInputPath = Join-Path $workRoot "input"
$packageOutputPath = Join-Path $outputRoot "packages"
$launcherPath = Join-Path $workRoot "launcher.rb"
$warbleConfigPath = Join-Path $workRoot "warble.dynamic.rb"

$javaHome = Get-JavaHome
$jrubyPath = Resolve-ToolPath -ToolName "jruby" -JavaHome ""
$jlinkPath = Resolve-ToolPath -ToolName "jlink" -JavaHome $javaHome
$jpackagePath = Resolve-ToolPath -ToolName "jpackage" -JavaHome $javaHome
$jdepsPath = Resolve-ToolPath -ToolName "jdeps" -JavaHome $javaHome

Write-Step "Projeto: $projectRoot"
Write-Step "Script alvo: $scriptRelativePath"
Write-Step "App: $displayName ($appId)"

New-CleanDirectory -Path $workRoot
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
New-CleanDirectory -Path $warblerInputPath

$launcherScript = @'
$LOAD_PATH.unshift(File.expand_path("../../..", __dir__))
load File.expand_path("../../../__SCRIPT_RELATIVE_PATH__", __dir__)
'@.Replace("__SCRIPT_RELATIVE_PATH__", $scriptRelativePath)

$extraDirs = @()
if ($scriptDirectoryRelativePath -and $scriptDirectoryRelativePath -ne ".") {
    $extraDirs += ($scriptDirectoryRelativePath -replace "\\", "/")
}

$extraDirsRuby = if ($extraDirs.Count -gt 0) {
    "[" + (($extraDirs | ForEach-Object { '"' + $_ + '"' }) -join ", ") + "]"
}
else {
    "[]"
}

$warbleConfig = @"
require_relative "../../../pipeline/packaging/warble/shared"

Warbler::Config.new do |config|
  Glauco::Packaging::WarbleShared.apply(
    config,
    executable: "build/packaging/$appId/launcher.rb",
    includes: [
      "$scriptRelativePath",
      "build/packaging/$appId/launcher.rb"
    ]
  )

  config.jar_name = "$appId"
  config.dirs |= $extraDirsRuby

  config.gem_excludes = [
    %r{(^|/)spec(/|$)},
    %r{(^|/)test(/|$)},
    %r{(^|/)examples(/|$)},
    %r{(^|/)doc(/|$)},
    %r{(^|/)docs(/|$)},
    %r{(^|/)benchmark(/|$)}
  ]

  config.gems += ["ruby_llm", "webrick"]
end
"@

Set-Content -LiteralPath $launcherPath -Value $launcherScript -Encoding UTF8
Set-Content -LiteralPath $warbleConfigPath -Value $warbleConfig -Encoding UTF8

if (-not $SkipJar) {
    Write-Step "Gerando jar com warbler"

    $generatedJarPath = Join-Path $projectRoot "$appId.jar"
    if (Test-Path $generatedJarPath) {
        Remove-Item -LiteralPath $generatedJarPath -Force
    }

    $previousWarbleConfig = $env:GLAUCO_WARBLE_CONFIG
    try {
        $env:GLAUCO_WARBLE_CONFIG = $warbleConfigPath
        Invoke-External -FilePath $jrubyPath -Arguments @("-S", "warble", "executable", "jar") -WorkingDirectory $projectRoot
    }
    finally {
        if ($null -eq $previousWarbleConfig) {
            Remove-Item Env:GLAUCO_WARBLE_CONFIG -ErrorAction SilentlyContinue
        }
        else {
            $env:GLAUCO_WARBLE_CONFIG = $previousWarbleConfig
        }
    }

    if (-not (Test-Path $generatedJarPath)) {
        throw "Warbler nao gerou o jar esperado: $generatedJarPath"
    }

    Move-Item -LiteralPath $generatedJarPath -Destination $jarOutputPath -Force
}

if (-not (Test-Path $jarOutputPath)) {
    throw "Jar nao encontrado em $jarOutputPath. Gere o jar primeiro ou remova -SkipJar."
}

if (-not $SkipJlink) {
    Write-Step "Gerando runtime customizado com jlink"

    $modules = Get-ModuleList -JdepsPath $jdepsPath -JarPath $jarOutputPath -ExtraModules $ExtraModules
    Write-Host "   Modulos: $($modules -join ',')"
    New-CleanDirectory -Path $runtimeOutputPath

    Invoke-External -FilePath $jlinkPath -Arguments @(
        "--add-modules", ($modules -join ","),
        "--output", $runtimeOutputPath,
        "--strip-debug",
        "--no-header-files",
        "--no-man-pages",
        "--compress=2"
    ) -WorkingDirectory $projectRoot
}

if (-not $SkipJpackage) {
    if (-not (Test-Path $runtimeOutputPath)) {
        throw "Runtime nao encontrado em $runtimeOutputPath. Gere o runtime ou remova -SkipJlink."
    }

    Write-Step "Gerando pacote(s) com jpackage"
    New-Item -ItemType Directory -Path $packageOutputPath -Force | Out-Null

    Copy-Item -LiteralPath $jarOutputPath -Destination (Join-Path $warblerInputPath "$appId.jar") -Force

    foreach ($packageType in $PackageTypes) {
        $arguments = @(
            "--name", $displayName,
            "--app-version", $Version,
            "--vendor", $Vendor,
            "--input", $warblerInputPath,
            "--main-jar", "$appId.jar",
            "--runtime-image", $runtimeOutputPath,
            "--dest", $packageOutputPath,
            "--type", $packageType
        )

        foreach ($javaOption in $JavaOptions) {
            $arguments += @("--java-options", $javaOption)
        }

        if ($IconPath) {
            $resolvedIconPath = Resolve-UserPath -PathValue $IconPath -BasePath $projectRoot
            $arguments += @("--icon", $resolvedIconPath)
        }

        Invoke-External -FilePath $jpackagePath -Arguments $arguments -WorkingDirectory $projectRoot
    }
}

if (-not $KeepWorkDir) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}

Write-Step "Empacotamento concluido"
Write-Host "Jar: $jarOutputPath"
if (-not $SkipJlink) {
    Write-Host "Runtime: $runtimeOutputPath"
}
if (-not $SkipJpackage) {
    Write-Host "Pacotes: $packageOutputPath"
}
