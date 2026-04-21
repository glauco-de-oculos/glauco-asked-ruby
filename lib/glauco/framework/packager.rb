require "fileutils"
require "optparse"
require "pathname"
require "rbconfig"
require "shellwords"
require "tmpdir"
require "English"

require_relative "version"
require_relative "warble_shared"

module Glauco
  module Framework
    class Packager
      attr_reader :project_root, :entry_path, :app_name, :output_dir, :image, :namespace, :base_image

      def initialize(project_root:, entry_path:, app_name:, output_dir:, image:, namespace:, base_image:)
        @project_root = File.expand_path(project_root)
        @entry_path = normalize_entry(entry_path)
        @app_name = app_name
        @output_dir = File.expand_path(output_dir, @project_root)
        @image = image
        @namespace = namespace
        @base_image = base_image
      end

      def build(write_container_files: true)
        ensure_build_runtime!
        ensure_entry_exists!
        FileUtils.mkdir_p(output_dir)
        work_root = File.join(project_root, "build", "packaging", slug)
        launcher_path = File.join(work_root, "launcher.rb")
        warble_config_path = File.join(work_root, "warble.dynamic.rb")
        framework_runtime_root = File.join(work_root, "glauco-framework")

        FileUtils.rm_rf(work_root)
        FileUtils.mkdir_p(work_root)
        stage_framework_runtime(framework_runtime_root)
        write_launcher(launcher_path, framework_runtime_root)
        write_warble_config(warble_config_path, launcher_path, framework_runtime_root)
        build_jar(warble_config_path)

        write_container_artifacts if write_container_files
      ensure
        FileUtils.rm_rf(work_root) if work_root && File.exist?(work_root)
      end

      def jar_path
        File.join(output_dir, "#{slug}.jar")
      end

      def dockerfile_path
        File.join(output_dir, "Dockerfile")
      end

      def kubernetes_manifest_path
        File.join(output_dir, "kubernetes.yaml")
      end

      def slug
        @slug ||= app_name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      end

      def self.run(argv = ARGV, stdout: $stdout, stderr: $stderr)
        command = argv.shift
        unless command == "build"
          stderr.puts("Uso: glauco-package build --entry app.rb --app-name meu-app")
          return 1
        end

        options = {
          project_root: Dir.pwd,
          entry_path: "bin/main.rb",
          app_name: "glauco-app",
          output_dir: "dist",
          image: "ghcr.io/CHANGE_ME/glauco/glauco-app:latest",
          namespace: "glauco",
          base_image: "eclipse-temurin:21-jre"
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Uso: glauco-package build [opcoes]"
          opts.on("--project-root PATH", "Raiz do projeto consumidor") { |value| options[:project_root] = value }
          opts.on("--entry PATH", "Script principal da app") { |value| options[:entry_path] = value }
          opts.on("--app-name NAME", "Nome da app/artefato") { |value| options[:app_name] = value }
          opts.on("--output DIR", "Diretorio de saida") { |value| options[:output_dir] = value }
          opts.on("--image NAME", "Imagem OCI para o manifesto") { |value| options[:image] = value }
          opts.on("--namespace NAME", "Namespace Kubernetes") { |value| options[:namespace] = value }
          opts.on("--base-image NAME", "Imagem base do Dockerfile") { |value| options[:base_image] = value }
        end

        parser.parse!(argv)

        packager = new(**options)
        packager.build

        stdout.puts("Jar: #{packager.jar_path}")
        stdout.puts("Dockerfile: #{packager.dockerfile_path}")
        stdout.puts("Kubernetes: #{packager.kubernetes_manifest_path}")
        0
      rescue OptionParser::ParseError, ArgumentError => e
        stderr.puts(e.message)
        1
      end

      private

      def normalize_entry(path)
        expanded = File.expand_path(path, project_root)
        relative = Pathname.new(expanded).relative_path_from(Pathname.new(project_root)).to_s
        relative.tr("\\", "/")
      end

      def ensure_entry_exists!
        absolute = File.join(project_root, entry_path)
        raise ArgumentError, "Entry nao encontrado: #{entry_path}" unless File.file?(absolute)
      end

      def build_jar(warble_config_path)
        root_jar = File.join(project_root, "#{slug}.jar")
        FileUtils.rm_f(root_jar)

        with_warble_config(warble_config_path) do
          system(RbConfig.ruby, "-S", "warble", "executable", "jar", chdir: project_root)
        end
        raise ArgumentError, "Falha ao gerar jar com warbler." unless $CHILD_STATUS.success?
        raise ArgumentError, "Warbler nao gerou #{root_jar}." unless File.exist?(root_jar)

        FileUtils.mv(root_jar, jar_path, force: true)
      end

      def with_warble_config(warble_config_path)
        config_dir = File.join(project_root, "config")
        target = File.join(config_dir, "warble.rb")
        backup = nil

        FileUtils.mkdir_p(config_dir)
        if File.exist?(target)
          backup = File.join(Dir.tmpdir, "glauco-warble-#{Process.pid}-#{Time.now.to_i}.rb")
          FileUtils.cp(target, backup)
        end

        FileUtils.cp(warble_config_path, target)
        yield
      ensure
        if backup && File.exist?(backup)
          FileUtils.cp(backup, target)
          FileUtils.rm_f(backup)
        else
          FileUtils.rm_f(target)
        end
      end

      def ensure_build_runtime!
        unless defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby"
          raise ArgumentError, "O build precisa rodar em JRuby. Execute via bundle exec usando o Ruby do projeto consumidor."
        end

        unless bundler_present?
          raise ArgumentError, "Execute o empacotamento com bundle exec para usar o Gemfile do projeto consumidor."
        end

        unless gem_declared?("warbler")
          raise ArgumentError, "Adicione gem 'warbler' ao Gemfile do projeto consumidor para gerar o jar."
        end
      end

      def bundler_present?
        defined?(Bundler) && Bundler.respond_to?(:definition)
      end

      def gem_declared?(name)
        Bundler.definition.dependencies.any? { |dependency| dependency.name == name }
      rescue StandardError
        false
      end

      def write_launcher(path, framework_runtime_root)
        File.write(
          path,
          <<~RUBY
            packaged_root = File.expand_path("../../..", __dir__)
            $LOAD_PATH.unshift(File.expand_path("glauco-framework/lib", __dir__))
            $LOAD_PATH.unshift(packaged_root)
            load File.expand_path(#{entry_path.inspect}, packaged_root)
          RUBY
        )
      end

      def write_warble_config(path, launcher_path, framework_runtime_root)
        File.write(
          path,
          <<~RUBY
            require "glauco/framework/warble_shared"

            Warbler::Config.new do |config|
              Glauco::Framework::WarbleShared.apply(
                config,
                project_root: #{project_root.inspect},
                executable: #{path_for_warbler(launcher_path).inspect},
                includes: [
                  #{entry_path.inspect},
                  #{path_for_warbler(launcher_path).inspect}
                ]
              )

              config.jar_name = #{slug.inspect}
              config.dirs += [
                #{path_for_warbler(framework_runtime_root).inspect}
              ]
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
          RUBY
        )
      end

      def stage_framework_runtime(target_root)
        gem_root = framework_gem_root
        FileUtils.mkdir_p(target_root)

        framework_runtime_entries.each do |entry|
          source = File.join(gem_root, entry)
          next unless File.exist?(source)

          target = File.join(target_root, entry)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp_r(source, target)
        end

        stage_llama_server_binary(target_root)
        prune_framework_runtime(target_root)
      end

      def path_for_warbler(path)
        Pathname.new(path).relative_path_from(Pathname.new(project_root)).to_s.tr("\\", "/")
      rescue ArgumentError
        path
      end

      def framework_runtime_entries
        [
          "core/framework",
          "bin",
          "jarlibs",
          "lib",
          "pipeline/executables/bin",
          "public"
        ]
      end

      def prune_framework_runtime(target_root)
        source_node_modules = File.join(framework_gem_root, "core/framework/web/node_modules")
        target_node_modules = File.join(target_root, "core/framework/web/node_modules")

        FileUtils.rm_rf(File.join(target_root, "core/framework/web/node_modules"))
        copy_framework_web_asset(
          source_node_modules,
          target_node_modules,
          "@carbon/web-components/custom-elements.json"
        )
        copy_framework_web_asset(
          source_node_modules,
          target_node_modules,
          "@carbon/styles/css"
        )

        Dir.glob(File.join(target_root, "core/framework/models/*.gguf")).each do |model_path|
          next if File.basename(model_path) == "gemma-4-e4b-it.gguf"

          FileUtils.rm_f(model_path)
        end
      end

      def stage_llama_server_binary(target_root)
        binary = ENV["GLAUCO_LLAMASERVER_BIN"]
        binary = find_executable("llama-server") if binary.nil? || binary.strip.empty?
        return unless binary && File.executable?(binary)

        target = File.join(target_root, "bin", "llama-server")
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(binary, target)
        FileUtils.chmod(0o755, target)
      end

      def find_executable(name)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
          candidate = File.join(dir, name)
          return candidate if File.executable?(candidate)
        end
        nil
      end

      def copy_framework_web_asset(source_node_modules, target_node_modules, relative_path)
        source = File.join(source_node_modules, relative_path)
        return unless File.exist?(source)

        target = File.join(target_node_modules, relative_path)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp_r(source, target)
      end

      def framework_gem_root
        File.expand_path("../../..", __dir__)
      end

      def write_container_artifacts
        File.write(dockerfile_path, dockerfile_content)
        File.write(kubernetes_manifest_path, kubernetes_manifest_content)
      end

      def dockerfile_content
        <<~DOCKERFILE
          ARG BASE_IMAGE=#{base_image}
          FROM ${BASE_IMAGE}

          WORKDIR /app

          RUN apt-get update \\
           && apt-get install -y --no-install-recommends \\
              xvfb \\
              xauth \\
              libgtk-3-0 \\
              libwebkit2gtk-4.1-0 \\
              libxtst6 \\
              libxrender1 \\
              libxi6 \\
              libxrandr2 \\
              libxss1 \\
              libasound2t64 \\
              fonts-dejavu-core \\
           && rm -rf /var/lib/apt/lists/* \\
           && addgroup --system --gid 10001 glauco \\
           && adduser --system --uid 10001 --ingroup glauco --home /home/glauco glauco \\
           && mkdir -p /home/glauco /app/tmp \\
           && chown -R 10001:10001 /home/glauco /app/tmp

          COPY #{File.basename(jar_path)} /app/#{File.basename(jar_path)}
          RUN printf '%s\\n' \\
              '#!/usr/bin/env sh' \\
              'set -eu' \\
              'if [ "${GLAUCO_USE_HOST_DISPLAY:-0}" = "1" ]; then' \\
              '  exec java -jar /app/#{File.basename(jar_path)}' \\
              'fi' \\
              'exec xvfb-run --auto-servernum --server-args="-screen 0 1280x800x24 -nolisten tcp" java -jar /app/#{File.basename(jar_path)}' \\
              > /app/glauco-entrypoint \\
           && chmod +x /app/glauco-entrypoint

          ENV HOME=/home/glauco
          ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -Dfile.encoding=UTF-8 -Djava.io.tmpdir=/app/tmp -Dorg.eclipse.swt.browser.DefaultType=webkit"
          ENV SWT_GTK3=1
          ENV DISPLAY=:99

          USER 10001:10001

          ENTRYPOINT ["/app/glauco-entrypoint"]
        DOCKERFILE
      end

      def kubernetes_manifest_content
        <<~YAML
          apiVersion: v1
          kind: Namespace
          metadata:
            name: #{namespace}
          ---
          apiVersion: v1
          kind: ServiceAccount
          metadata:
            name: #{slug}
            namespace: #{namespace}
          automountServiceAccountToken: false
          ---
          apiVersion: apps/v1
          kind: Deployment
          metadata:
            name: #{slug}
            namespace: #{namespace}
          spec:
            replicas: 1
            selector:
              matchLabels:
                app: #{slug}
            template:
              metadata:
                labels:
                  app: #{slug}
              spec:
                serviceAccountName: #{slug}
                automountServiceAccountToken: false
                securityContext:
                  seccompProfile:
                    type: RuntimeDefault
                containers:
                  - name: #{slug}
                    image: #{image}
                    imagePullPolicy: IfNotPresent
                    resources:
                      requests:
                        cpu: 250m
                        memory: 512Mi
                      limits:
                        cpu: "1"
                        memory: 1Gi
                    securityContext:
                      runAsNonRoot: true
                      runAsUser: 10001
                      runAsGroup: 10001
                      readOnlyRootFilesystem: true
                      allowPrivilegeEscalation: false
                      capabilities:
                        drop:
                          - ALL
                    volumeMounts:
                      - name: tmp
                        mountPath: /tmp
                      - name: app-tmp
                        mountPath: /app/tmp
                      - name: home
                        mountPath: /home/glauco
                      - name: public
                        mountPath: /app/public
                volumes:
                  - name: tmp
                    emptyDir: {}
                  - name: app-tmp
                    emptyDir: {}
                  - name: home
                    emptyDir: {}
                  - name: public
                    emptyDir: {}
        YAML
      end
    end
  end
end
