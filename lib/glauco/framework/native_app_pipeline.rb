# frozen_string_literal: true

require "fileutils"
require "optparse"
require "rbconfig"
require "shellwords"
require "English"

require_relative "packager"

module Glauco
  module Framework
    class NativeAppPipeline
      attr_reader :packager, :display_name, :version, :vendor, :icon_path, :java_options,
                  :jpackage_bin, :package_type, :console, :skip_jpackage

      def initialize(packager:, display_name:, version:, vendor:, icon_path:, java_options:,
                     jpackage_bin:, package_type:, console:, skip_jpackage:)
        @packager = packager
        @display_name = display_name
        @version = version
        @vendor = vendor
        @icon_path = icon_path
        @java_options = java_options
        @jpackage_bin = jpackage_bin
        @package_type = package_type
        @console = console
        @skip_jpackage = skip_jpackage
      end

      def build
        packager.build(write_container_files: false)
        build_native_app unless skip_jpackage
        write_runner_scripts
      end

      def slug
        packager.slug
      end

      def output_dir
        packager.output_dir
      end

      def packages_dir
        File.join(output_dir, "packages")
      end

      def executable_path
        return File.join(packages_dir, "#{display_name}.app", "Contents", "MacOS", display_name) if macos?
        return File.join(packages_dir, display_name, "#{display_name}.exe") if windows?

        File.join(packages_dir, display_name, "bin", display_name)
      end

      def run_bat_path
        File.join(output_dir, "run-#{slug}.bat")
      end

      def run_ps1_path
        File.join(output_dir, "run-#{slug}.ps1")
      end

      def run_sh_path
        File.join(output_dir, "run-#{slug}.sh")
      end

      def shortcut_ps1_path
        File.join(output_dir, "create-#{slug}-desktop-shortcut.ps1")
      end

      def desktop_entry_path
        File.join(output_dir, "#{slug}.desktop")
      end

      def self.run(argv = ARGV, stdout: $stdout, stderr: $stderr)
        command = argv.shift
        unless command == "build"
          stderr.puts("Uso: glauco-native-app build --entry app.rb --app-name meu-app")
          return 1
        end

        options = {
          project_root: Dir.pwd,
          entry_path: "bin/main.rb",
          app_name: "glauco-app",
          output_dir: "dist",
          version: "1.0.0",
          vendor: "Glauco",
          icon_path: nil,
          java_options: [
            "--enable-native-access=ALL-UNNAMED",
            "-Dfile.encoding=UTF-8"
          ],
          jpackage_bin: nil,
          package_type: "app-image",
          console: false,
          skip_jpackage: false,
          agent_runtime: "auto"
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Uso: glauco-native-app build [opcoes]"
          opts.on("--project-root PATH", "Raiz do projeto consumidor") { |value| options[:project_root] = value }
          opts.on("--entry PATH", "Script principal da app") { |value| options[:entry_path] = value }
          opts.on("--app-name NAME", "Nome da app/artefato") { |value| options[:app_name] = value }
          opts.on("--output DIR", "Diretorio de saida") { |value| options[:output_dir] = value }
          opts.on("--version VERSION", "Versao do app") { |value| options[:version] = value }
          opts.on("--vendor NAME", "Vendor do app") { |value| options[:vendor] = value }
          opts.on("--icon PATH", "Icone do app") { |value| options[:icon_path] = value }
          opts.on("--java-option VALUE", "Opcao Java extra") { |value| options[:java_options] << value }
          opts.on("--jpackage-bin PATH", "Executavel jpackage") { |value| options[:jpackage_bin] = value }
          opts.on("--package-type TYPE", "Tipo jpackage: app-image, exe, msi, deb, rpm") { |value| options[:package_type] = value }
          opts.on("--console", "Abre console junto com o app quando a plataforma suporta") { options[:console] = true }
          opts.on("--win-console", "Alias de --console no Windows") { options[:console] = true }
          opts.on("--skip-jpackage", "Gera jar e runners sem executar jpackage") { options[:skip_jpackage] = true }
          opts.on("--agent-runtime MODE", "auto, include ou none para llama-server/modelo GGUF") { |value| options[:agent_runtime] = value }
        end

        parser.parse!(argv)

        packager = Packager.new(
          project_root: options.fetch(:project_root),
          entry_path: options.fetch(:entry_path),
          app_name: options.fetch(:app_name),
          output_dir: options.fetch(:output_dir),
          image: "#{options.fetch(:app_name)}:local",
          namespace: "glauco",
          base_image: "eclipse-temurin:21-jre",
          agent_runtime: options.fetch(:agent_runtime)
        )

        pipeline = new(
          packager: packager,
          display_name: options.fetch(:app_name),
          version: options.fetch(:version),
          vendor: options.fetch(:vendor),
          icon_path: options[:icon_path],
          java_options: options.fetch(:java_options),
          jpackage_bin: options[:jpackage_bin],
          package_type: options.fetch(:package_type),
          console: options.fetch(:console),
          skip_jpackage: options.fetch(:skip_jpackage)
        )
        pipeline.build

        stdout.puts("Jar: #{packager.jar_path}")
        stdout.puts("App nativo: #{pipeline.executable_path}") unless pipeline.skip_jpackage
        stdout.puts("Runner shell: #{pipeline.run_sh_path}") unless pipeline.windows?
        stdout.puts("Runner BAT: #{pipeline.run_bat_path}") if pipeline.windows?
        stdout.puts("Runner PowerShell: #{pipeline.run_ps1_path}") if pipeline.windows?
        stdout.puts("Atalho Desktop Windows: #{pipeline.shortcut_ps1_path}") if pipeline.windows?
        stdout.puts("Desktop entry Linux: #{pipeline.desktop_entry_path}") if pipeline.linux?
        0
      rescue OptionParser::ParseError, ArgumentError => e
        stderr.puts(e.message)
        1
      end

      def windows?
        host_os =~ /mswin|mingw|cygwin/
      end

      def linux?
        host_os =~ /linux/
      end

      private

      def build_native_app
        FileUtils.rm_rf(packages_dir)
        FileUtils.mkdir_p(jpackage_input_dir)
        FileUtils.cp(packager.jar_path, File.join(jpackage_input_dir, File.basename(packager.jar_path)))

        args = [
          "--name", display_name,
          "--app-version", version,
          "--vendor", vendor,
          "--input", jpackage_input_dir,
          "--main-jar", File.basename(packager.jar_path),
          "--dest", packages_dir,
          "--type", package_type
        ]
        java_options.each { |option| args += ["--java-options", option] }
        args += ["--icon", File.expand_path(icon_path, packager.project_root)] if icon_path
        args << "--win-console" if windows? && console

        system(resolved_jpackage_bin, *args, chdir: packager.project_root)
        raise ArgumentError, "Falha ao gerar app nativo com jpackage." unless $CHILD_STATUS.success?
      end

      def jpackage_input_dir
        File.join(output_dir, "jpackage-input")
      end

      def resolved_jpackage_bin
        return jpackage_bin if jpackage_bin && !jpackage_bin.strip.empty?

        java_home = ENV["JAVA_HOME"]
        if java_home && !java_home.strip.empty?
          candidate = File.join(java_home, "bin", windows? ? "jpackage.exe" : "jpackage")
          return candidate if File.exist?(candidate)
        end

        command = find_executable(windows? ? "jpackage.exe" : "jpackage")
        return command if command

        raise ArgumentError, "jpackage nao encontrado. Instale/aponte um JDK com --jpackage-bin."
      end

      def find_executable(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          candidate = File.join(dir, name)
          return candidate if File.executable?(candidate)
        end
        nil
      end

      def write_runner_scripts
        FileUtils.mkdir_p(output_dir)

        if windows?
          File.write(run_bat_path, run_bat_content)
          File.write(run_ps1_path, run_ps1_content)
          File.write(shortcut_ps1_path, shortcut_ps1_content)
        else
          File.write(run_sh_path, run_sh_content)
          FileUtils.chmod(0o755, run_sh_path)
          File.write(desktop_entry_path, desktop_entry_content) if linux?
        end
      end

      def run_bat_content
        target = skip_jpackage ? "java -jar #{windows_quote(packager.jar_path)}" : windows_quote(executable_path)

        <<~BAT
          @echo off
          cd /d "%~dp0"
          #{target}
        BAT
      end

      def run_ps1_content
        target = skip_jpackage ? "& 'java' '-jar' #{powershell_quote(packager.jar_path)}" : "& #{powershell_quote(executable_path)}"

        <<~POWERSHELL
          Set-StrictMode -Version Latest
          $ErrorActionPreference = "Stop"
          Set-Location $PSScriptRoot
          #{target}
        POWERSHELL
      end

      def run_sh_content
        target = skip_jpackage ? "exec java -jar #{shell_quote(packager.jar_path)}" : "exec #{shell_quote(executable_path)}"

        <<~SH
          #!/usr/bin/env sh
          set -eu
          cd "$(dirname "$0")"
          #{target}
        SH
      end

      def shortcut_ps1_content
        <<~POWERSHELL
          Set-StrictMode -Version Latest
          $ErrorActionPreference = "Stop"
          $shell = New-Object -ComObject WScript.Shell
          $desktop = [Environment]::GetFolderPath("Desktop")
          $shortcut = $shell.CreateShortcut((Join-Path $desktop #{powershell_quote("#{display_name}.lnk")}))
          $shortcut.TargetPath = #{powershell_quote(skip_jpackage ? run_bat_path : executable_path)}
          $shortcut.WorkingDirectory = #{powershell_quote(skip_jpackage ? output_dir : File.dirname(executable_path))}
          $shortcut.Save()
        POWERSHELL
      end

      def desktop_entry_content
        <<~DESKTOP
          [Desktop Entry]
          Type=Application
          Name=#{display_name}
          Exec=#{executable_path}
          Terminal=#{console ? "true" : "false"}
          Categories=Utility;
        DESKTOP
      end

      def windows_quote(value)
        %("#{value.to_s.gsub('"', '""')}")
      end

      def powershell_quote(value)
        "'#{value.to_s.gsub("'", "''")}'"
      end

      def shell_quote(value)
        Shellwords.escape(value.to_s)
      end

      def macos?
        host_os =~ /darwin/
      end

      def host_os
        RbConfig::CONFIG["host_os"]
      end
    end
  end
end
