# frozen_string_literal: true

require_relative "native_app_pipeline"

module Glauco
  module Framework
    class WindowsAppPipeline < NativeAppPipeline
      def self.run(argv = ARGV, stdout: $stdout, stderr: $stderr)
        NativeAppPipeline.run(argv, stdout: stdout, stderr: stderr)
      end
    end
  end
end
