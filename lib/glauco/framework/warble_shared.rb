require "pathname"

module Glauco
  module Framework
    module WarbleShared
      module_function

      def apply(config, project_root:, executable:, includes:)
        root = File.expand_path(project_root)

        config.jar_name = "glauco-app"
        config.jar_extension = "jar"
        config.dirs = package_dirs(root)
        config.includes = Array(includes)
        config.excludes = package_excludes(root)
        config.executable = executable
        config.features = ["executable"]
        config.java_libs += java_libs(root)
        config.gem_dependencies = true
        config.bundler = false
      end

      def package_dirs(project_root)
        candidates = [
          "app",
          "bin",
          "config",
          "examples",
          "jarlibs",
          "lib",
          "pipeline/executables/bin",
          "public",
          "src",
          "core/framework/web/node_modules"
        ]

        candidates.select { |path| File.exist?(File.join(project_root, path)) }
      end

      def package_excludes(project_root)
        excludes = []
        node_modules_bin = File.join(project_root, "core/framework/web/node_modules/.bin")
        node_modules_maps = File.join(project_root, "core/framework/web/node_modules")

        excludes << "core/framework/web/node_modules/.bin" if File.exist?(node_modules_bin)
        excludes << "core/framework/web/node_modules/**/*.map" if File.exist?(node_modules_maps)
        excludes << "dist"
        excludes << "dist/**/*"
        excludes
      end

      def java_libs(project_root)
        libs = Dir.glob(File.join(project_root, "jarlibs", "*.jar"))
        gem_root = File.expand_path("../../..", __dir__)
        platform_java_libs(libs + Dir.glob(File.join(gem_root, "jarlibs", "*.jar")))
      end

      def platform_java_libs(libs)
        swt_jar = platform_swt_jar(libs)
        filtered = libs.reject { |path| swt_runtime_jar?(File.basename(path)) }
        swt_jar ? filtered + [swt_jar] : filtered
      end

      def platform_swt_jar(libs)
        candidates = if Gem.win_platform?
                       ["swt-win32.jar", /^org\.eclipse\.swt\.win32\.win32\./]
                     elsif RbConfig::CONFIG["host_os"] =~ /linux/
                       [/^swt\.gtk\./, /^org\.eclipse\.swt\.gtk\./, "swt.jar"]
                     elsif RbConfig::CONFIG["host_os"] =~ /darwin/
                       [/^org\.eclipse\.swt\.cocoa\./, "swt.jar"]
                     else
                       ["swt.jar"]
                     end

        candidates.each do |candidate|
          found = libs.find do |path|
            basename = File.basename(path)
            candidate.is_a?(Regexp) ? basename.match?(candidate) : basename == candidate
          end
          return found if found
        end

        nil
      end

      def swt_runtime_jar?(basename)
        basename == "swt.jar" ||
          basename == "swt-win32.jar" ||
          basename.start_with?("swt.gtk.") ||
          basename.start_with?("org.eclipse.swt.")
      end
    end
  end
end
