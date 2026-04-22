# frozen_string_literal: true

require "fileutils"
require "optparse"
require "rbconfig"
require "shellwords"
require "English"

require_relative "packager"

module Glauco
  module Framework
    class ContainerPipeline
      attr_reader :packager, :docker_bin, :container_name, :ports, :env, :skip_docker_build

      def initialize(packager:, docker_bin:, container_name:, ports:, env:, skip_docker_build:)
        @packager = packager
        @docker_bin = docker_bin
        @container_name = container_name
        @ports = ports
        @env = env
        @skip_docker_build = skip_docker_build
      end

      def build
        packager.build
        build_container_image unless skip_docker_build
        write_runner_scripts
      end

      def image
        packager.image
      end

      def slug
        packager.slug
      end

      def output_dir
        packager.output_dir
      end

      def run_bat_path
        File.join(output_dir, "run-#{slug}-container.bat")
      end

      def run_ps1_path
        File.join(output_dir, "run-#{slug}-container.ps1")
      end

      def self.run(argv = ARGV, stdout: $stdout, stderr: $stderr)
        command = argv.shift
        unless command == "build"
          stderr.puts("Uso: glauco-containerize build --entry app.rb --app-name meu-app --image minha-imagem:local")
          return 1
        end

        options = {
          project_root: Dir.pwd,
          entry_path: "bin/main.rb",
          app_name: "glauco-app",
          output_dir: "dist",
          image: "glauco-app:local",
          namespace: "glauco",
          base_image: "eclipse-temurin:21-jre",
          docker_bin: "docker",
          container_name: nil,
          ports: [],
          env: [],
          skip_docker_build: false,
          agent_runtime: "auto"
        }

        parser = OptionParser.new do |opts|
          opts.banner = "Uso: glauco-containerize build [opcoes]"
          opts.on("--project-root PATH", "Raiz do projeto consumidor") { |value| options[:project_root] = value }
          opts.on("--entry PATH", "Script principal da app") { |value| options[:entry_path] = value }
          opts.on("--app-name NAME", "Nome da app/artefato") { |value| options[:app_name] = value }
          opts.on("--output DIR", "Diretorio de saida") { |value| options[:output_dir] = value }
          opts.on("--image NAME", "Tag da imagem Docker/OCI") { |value| options[:image] = value }
          opts.on("--namespace NAME", "Namespace Kubernetes") { |value| options[:namespace] = value }
          opts.on("--base-image NAME", "Imagem base do Dockerfile") { |value| options[:base_image] = value }
          opts.on("--docker-bin PATH", "Executavel Docker") { |value| options[:docker_bin] = value }
          opts.on("--container-name NAME", "Nome do container local") { |value| options[:container_name] = value }
          opts.on("--port MAP", "Mapeamento de porta, ex: 8080:8080") { |value| options[:ports] << value }
          opts.on("--env KEY=VALUE", "Variavel de ambiente para docker run") { |value| options[:env] << value }
          opts.on("--skip-docker-build", "Gera artefatos e atalhos sem rodar docker build") { options[:skip_docker_build] = true }
          opts.on("--agent-runtime MODE", "auto, include ou none para llama-server/modelo GGUF") { |value| options[:agent_runtime] = value }
        end

        parser.parse!(argv)

        packager = Packager.new(
          project_root: options.fetch(:project_root),
          entry_path: options.fetch(:entry_path),
          app_name: options.fetch(:app_name),
          output_dir: options.fetch(:output_dir),
          image: options.fetch(:image),
          namespace: options.fetch(:namespace),
          base_image: options.fetch(:base_image),
          agent_runtime: options.fetch(:agent_runtime)
        )

        pipeline = new(
          packager: packager,
          docker_bin: options.fetch(:docker_bin),
          container_name: options[:container_name] || packager.slug,
          ports: options.fetch(:ports),
          env: options.fetch(:env),
          skip_docker_build: options.fetch(:skip_docker_build)
        )
        pipeline.build

        stdout.puts("Jar: #{packager.jar_path}")
        stdout.puts("Imagem: #{pipeline.image}")
        stdout.puts("Dockerfile: #{packager.dockerfile_path}")
        stdout.puts("Kubernetes: #{packager.kubernetes_manifest_path}")
        stdout.puts("Atalho Windows: #{pipeline.run_bat_path}")
        stdout.puts("Runner PowerShell: #{pipeline.run_ps1_path}")
        0
      rescue OptionParser::ParseError, ArgumentError => e
        stderr.puts(e.message)
        1
      end

      private

      def build_container_image
        system(
          docker_bin,
          "build",
          "-f",
          packager.dockerfile_path,
          "-t",
          image,
          output_dir,
          chdir: packager.project_root
        )
        raise ArgumentError, "Falha ao gerar imagem Docker #{image}." unless $CHILD_STATUS.success?
      end

      def write_runner_scripts
        FileUtils.mkdir_p(output_dir)
        File.write(run_bat_path, run_bat_content)
        File.write(run_ps1_path, run_ps1_content)
      end

      def docker_run_args
        args = ["run", "--rm", "--name", container_name]
        args += ["-e", "GLAUCO_USE_HOST_DISPLAY=0"]
        env.each { |value| args += ["-e", value] }
        ports.each { |value| args += ["-p", value] }
        args << image
        args
      end

      def run_bat_content
        command = ([docker_bin] + docker_run_args).map { |part| windows_quote(part) }.join(" ")

        <<~BAT
          @echo off
          cd /d "%~dp0"
          #{command}
          pause
        BAT
      end

      def run_ps1_content
        command = ([docker_bin] + docker_run_args).map { |part| powershell_quote(part) }.join(" ")

        <<~POWERSHELL
          Set-StrictMode -Version Latest
          $ErrorActionPreference = "Stop"
          Set-Location $PSScriptRoot
          & #{command}
        POWERSHELL
      end

      def windows_quote(value)
        %("#{value.to_s.gsub('"', '""')}")
      end

      def powershell_quote(value)
        "'#{value.to_s.gsub("'", "''")}'"
      end
    end
  end
end
