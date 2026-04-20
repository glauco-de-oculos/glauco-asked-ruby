require "bundler" rescue nil
require "fileutils"
require_relative "glauco/framework/version"

module Glauco
  module Framework
    GEM_ROOT = File.expand_path("..", __dir__)
    FRAMEWORK_ROOT = File.join(GEM_ROOT, "core", "framework")
    PUBLIC_ASSETS_DIR = File.join(GEM_ROOT, "public")
    JARLIBS_ROOT = File.join(GEM_ROOT, "jarlibs")
    WEB_ROOT = File.join(FRAMEWORK_ROOT, "web")

    module_function

    def app_root
      env_root = ENV["GLAUCO_PROJECT_ROOT"]
      return File.expand_path(env_root) unless blank?(env_root)

      if defined?(Bundler) && Bundler.respond_to?(:root)
        Bundler.root.to_s
      else
        Dir.pwd
      end
    end

    def app_public_dir
      File.join(app_root, "public")
    end

    def ensure_public_assets!
      FileUtils.mkdir_p(app_public_dir)

      Dir.glob(File.join(PUBLIC_ASSETS_DIR, "*")).each do |source|
        next unless File.file?(source)
        next if File.basename(source) == "index.html"

        target = File.join(app_public_dir, File.basename(source))
        next if File.exist?(target) && File.mtime(target) >= File.mtime(source)

        FileUtils.cp(source, target)
      end

      stale_index = File.join(app_public_dir, "index.html")
      FileUtils.rm_f(stale_index)
    end

    def blank?(value)
      value.nil? || value.strip.empty?
    end
  end
end

PROJECT_ROOT = Glauco::Framework.app_root unless defined?(PROJECT_ROOT)
GLAUCO_GEM_ROOT = Glauco::Framework::GEM_ROOT unless defined?(GLAUCO_GEM_ROOT)
JARLIBS_DIR = Glauco::Framework::JARLIBS_ROOT unless defined?(JARLIBS_DIR)
PUBLIC_DIR = Glauco::Framework.app_public_dir unless defined?(PUBLIC_DIR)
FRAMEWORK_WEB_DIR = Glauco::Framework::WEB_ROOT unless defined?(FRAMEWORK_WEB_DIR)
NODE_MODULES_DIR = File.join(FRAMEWORK_WEB_DIR, "node_modules") unless defined?(NODE_MODULES_DIR)

Glauco::Framework.ensure_public_assets!

require File.join(Glauco::Framework::FRAMEWORK_ROOT, "glauco-framework")
