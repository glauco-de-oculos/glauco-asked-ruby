module Glauco
  module Packaging
    module WarbleShared
      module_function

      def apply(config, executable:, includes:)
        config.jar_name = "image_viewer"
        config.jar_extension = "jar"

        config.dirs = [
          "core",
          "public",
          "examples",
          "jarlibs",
          "bin",
          "pipeline/executables/bin",
          "core/framework/web/node_modules"
        ]

        config.includes = Array(includes)
        config.excludes = [
          "core/framework/web/node_modules/.bin",
          "core/framework/web/node_modules/**/*.map"
        ]
        config.executable = executable
        config.features = ["executable"]
        config.java_libs += Dir.glob("jarlibs/*.jar")
        config.gem_dependencies = true
        config.bundler = false
      end
    end
  end
end
