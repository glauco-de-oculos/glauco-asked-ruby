require "bundler" rescue nil
require "fileutils"
require "rbconfig"
require "tmpdir"
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
    rescue Bundler::GemfileNotFound
      Dir.pwd
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

    def ensure_packaged_llama_server!
      return unless blank?(ENV["GLAUCO_LLAMASERVER_BIN"])

      source = packaged_llama_server_source
      return unless File.exist?(source)

      target_dir = File.join(Dir.tmpdir, "glauco-framework-runtime")
      target = File.join(target_dir, File.basename(source))
      FileUtils.mkdir_p(target_dir)

      if !File.exist?(target) || File.size(target) != File.size(source)
        File.binwrite(target, File.binread(source))
        FileUtils.chmod(0o755, target)
      end

      ENV["GLAUCO_LLAMASERVER_BIN"] = target
    rescue StandardError => e
      warn "[Glauco::Framework] falha ao preparar llama-server empacotado: #{e.class} - #{e.message}"
    end

    def ensure_packaged_llama_model!
      return unless blank?(ENV["GLAUCO_LLAMASERVER_MODEL_PATH"])

      model = Dir.glob(File.join(FRAMEWORK_ROOT, "models", "*.gguf")).find do |path|
        !File.basename(path).downcase.include?("mmproj")
      end
      return unless model

      ENV["GLAUCO_LLAMASERVER_MODEL_PATH"] = model
    end

    def packaged_llama_server_source
      names = windows? ? ["llama-server.exe", "llama-server"] : ["llama-server", "llama-server.exe"]
      names.map { |name| File.join(GEM_ROOT, "bin", name) }.find { |path| File.exist?(path) }
    end

    def windows?
      RbConfig::CONFIG["host_os"] =~ /mswin|mingw|cygwin/
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
Glauco::Framework.ensure_packaged_llama_server!
Glauco::Framework.ensure_packaged_llama_model!

require File.join(Glauco::Framework::FRAMEWORK_ROOT, "glauco-framework")
