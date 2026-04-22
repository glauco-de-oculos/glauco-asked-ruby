# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"

require "glauco/framework/container_pipeline"
require "glauco/framework/packager"

class PackagerPackageTest < Minitest::Test
  def test_build_writes_complete_container_package_with_kubernetes_manifest
    Dir.mktmpdir("glauco-packager-test") do |project_root|
      FileUtils.mkdir_p(File.join(project_root, "bin"))
      File.write(File.join(project_root, "bin", "main.rb"), "puts 'hello from glauco'\n")

      packager = Glauco::Framework::Packager.new(
        project_root: project_root,
        entry_path: "bin/main.rb",
        app_name: "My Glauco App",
        output_dir: "dist",
        image: "ghcr.io/example/glauco/my-glauco-app:test",
        namespace: "apps",
        base_image: "eclipse-temurin:21-jre-alpine"
      )

      def packager.ensure_build_runtime!; end
      def packager.build_jar(_warble_config_path)
        File.write(jar_path, "fake jar")
      end

      packager.build

      assert_path_exists File.join(project_root, "dist", "my-glauco-app.jar")

      dockerfile = File.read(File.join(project_root, "dist", "Dockerfile"))
      assert_includes dockerfile, "ARG BASE_IMAGE=eclipse-temurin:21-jre-alpine"
      assert_includes dockerfile, "xvfb"
      assert_includes dockerfile, "libgtk-3-0"
      assert_includes dockerfile, "libwebkit2gtk-4.1-0"
      assert_includes dockerfile, "COPY my-glauco-app.jar /app/my-glauco-app.jar"
      assert_includes dockerfile, "GLAUCO_USE_HOST_DISPLAY"
      assert_includes dockerfile, "xvfb-run --auto-servernum"
      assert_includes dockerfile, 'ENTRYPOINT ["/app/glauco-entrypoint"]'

      documents = YAML.load_stream(File.read(File.join(project_root, "dist", "kubernetes.yaml")))
      namespace, service_account, deployment = documents

      assert_equal "Namespace", namespace.fetch("kind")
      assert_equal "apps", namespace.fetch("metadata").fetch("name")

      assert_equal "ServiceAccount", service_account.fetch("kind")
      assert_equal "my-glauco-app", service_account.fetch("metadata").fetch("name")
      assert_equal "apps", service_account.fetch("metadata").fetch("namespace")
      assert_equal false, service_account.fetch("automountServiceAccountToken")

      assert_equal "Deployment", deployment.fetch("kind")
      assert_equal "my-glauco-app", deployment.fetch("metadata").fetch("name")
      assert_equal "apps", deployment.fetch("metadata").fetch("namespace")

      pod_spec = deployment.fetch("spec").fetch("template").fetch("spec")
      assert_equal "my-glauco-app", pod_spec.fetch("serviceAccountName")
      assert_equal false, pod_spec.fetch("automountServiceAccountToken")
      assert_equal "RuntimeDefault", pod_spec.fetch("securityContext").fetch("seccompProfile").fetch("type")

      container = pod_spec.fetch("containers").first
      assert_equal "my-glauco-app", container.fetch("name")
      assert_equal "ghcr.io/example/glauco/my-glauco-app:test", container.fetch("image")
      assert_equal "IfNotPresent", container.fetch("imagePullPolicy")
      assert_equal({ "cpu" => "250m", "memory" => "512Mi" }, container.fetch("resources").fetch("requests"))
      assert_equal({ "cpu" => "1", "memory" => "1Gi" }, container.fetch("resources").fetch("limits"))
      assert_equal true, container.fetch("securityContext").fetch("runAsNonRoot")
      assert_equal true, container.fetch("securityContext").fetch("readOnlyRootFilesystem")
      assert_equal false, container.fetch("securityContext").fetch("allowPrivilegeEscalation")
      assert_equal ["ALL"], container.fetch("securityContext").fetch("capabilities").fetch("drop")
      assert_equal({ "name" => "tmp", "mountPath" => "/tmp" }, container.fetch("volumeMounts").first)
      assert_includes container.fetch("volumeMounts"), { "name" => "app-tmp", "mountPath" => "/app/tmp" }
      assert_includes container.fetch("volumeMounts"), { "name" => "home", "mountPath" => "/home/glauco" }
      assert_includes container.fetch("volumeMounts"), { "name" => "public", "mountPath" => "/app/public" }
      assert_equal({ "name" => "tmp", "emptyDir" => {} }, pod_spec.fetch("volumes").first)
      assert_includes pod_spec.fetch("volumes"), { "name" => "app-tmp", "emptyDir" => {} }
      assert_includes pod_spec.fetch("volumes"), { "name" => "home", "emptyDir" => {} }
      assert_includes pod_spec.fetch("volumes"), { "name" => "public", "emptyDir" => {} }
    end
  end

  def test_container_pipeline_writes_docker_runner_scripts
    Dir.mktmpdir("glauco-container-pipeline-test") do |project_root|
      FileUtils.mkdir_p(File.join(project_root, "bin"))
      File.write(File.join(project_root, "bin", "main.rb"), "puts 'hello from container'\n")

      packager = Glauco::Framework::Packager.new(
        project_root: project_root,
        entry_path: "bin/main.rb",
        app_name: "My Glauco App",
        output_dir: "dist",
        image: "my-glauco-app:local",
        namespace: "apps",
        base_image: "eclipse-temurin:21-jre"
      )

      def packager.ensure_build_runtime!; end
      def packager.build_jar(_warble_config_path)
        File.write(jar_path, "fake jar")
      end

      pipeline = Glauco::Framework::ContainerPipeline.new(
        packager: packager,
        docker_bin: "docker",
        container_name: "my-glauco-app",
        ports: ["8080:8080"],
        env: ["OLLAMA_HOST=http://ollama:11434"],
        skip_docker_build: true
      )
      pipeline.build

      bat = File.read(File.join(project_root, "dist", "run-my-glauco-app-container.bat"))
      assert_includes bat, '"docker" "run" "--rm" "--name" "my-glauco-app"'
      assert_includes bat, '"-e" "GLAUCO_USE_HOST_DISPLAY=0"'
      assert_includes bat, '"-e" "OLLAMA_HOST=http://ollama:11434"'
      assert_includes bat, '"-p" "8080:8080"'
      assert_includes bat, '"my-glauco-app:local"'
      assert_includes bat, "pause"

      ps1 = File.read(File.join(project_root, "dist", "run-my-glauco-app-container.ps1"))
      assert_includes ps1, "& 'docker' 'run' '--rm' '--name' 'my-glauco-app'"
      assert_includes ps1, "'my-glauco-app:local'"
    end
  end

  def test_agent_entry_requires_and_stages_llama_runtime
    Dir.mktmpdir("glauco-agent-packager-test") do |project_root|
      FileUtils.mkdir_p(File.join(project_root, "bin"))
      File.write(File.join(project_root, "bin", "main.rb"), "GlaucoBasicPlasticAgent.new\n")

      fake_runtime = File.join(project_root, Gem.win_platform? ? "llama-server.exe" : "llama-server")
      fake_model = File.join(project_root, "model.gguf")
      File.write(fake_runtime, "fake runtime")
      FileUtils.chmod(0o755, fake_runtime)
      File.write(fake_model, "fake gguf")

      packager = Glauco::Framework::Packager.new(
        project_root: project_root,
        entry_path: "bin/main.rb",
        app_name: "Agent App",
        output_dir: "dist",
        image: "agent-app:local",
        namespace: "apps",
        base_image: "eclipse-temurin:21-jre"
      )

      def packager.ensure_build_runtime!; end
      def packager.build_jar(_warble_config_path)
        runtime_name = Gem.win_platform? ? "llama-server.exe" : "llama-server"
        staged_runtime = File.join(project_root, "build", "packaging", slug, "glauco-framework", "bin", runtime_name)
        staged_model = File.join(project_root, "build", "packaging", slug, "glauco-framework", "core", "framework", "models", "model.gguf")

        raise "runtime not staged" unless File.exist?(staged_runtime)
        raise "model not staged" unless File.exist?(staged_model)

        File.write(jar_path, "fake jar")
      end

      with_env(
        "GLAUCO_LLAMASERVER_BIN" => fake_runtime,
        "GLAUCO_LLAMASERVER_MODEL_PATH" => fake_model
      ) do
        packager.build(write_container_files: false)
      end

      assert_path_exists File.join(project_root, "dist", "agent-app.jar")
    end
  end

  private

  def with_env(values)
    previous = values.to_h { |key, _| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
