Warbler::Config.new do |config|
  # ========================================
  # 🔥 TIPO: standalone JAR
  # ========================================
  config.jar_name = "image_viewer"
  config.jar_extension = "jar"

  # ========================================
  # 📦 INCLUIR ARQUIVOS
  # ========================================
  config.dirs = %w[
    public
    node_modules
    examples
    glauco-framework
    jarlibs
  ]

  config.includes = FileList[
    "carbon.js",
    "basic_ui_with_fs_io.rb"
  ]

  config.excludes = FileList[
    "node_modules/.bin",
    "node_modules/**/*.map"
  ]

  # ========================================
  # 🔥 ENTRYPOINT (ESSENCIAL)
  # ========================================
  config.executable = "examples/basic_ui_with_fs_io.rb"
  config.features = %w(executable)

  # ========================================
  # 🔥 SWT (JARs)
  # ========================================
  config.java_libs += FileList["jarlibs/*.jar"]

  config.gem_dependencies = true

  # ========================================
  # 🔥 SEM BUNDLER
  # ========================================
  config.bundler = false
end