# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "yaml"

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
end
