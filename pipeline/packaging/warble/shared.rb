require_relative "../../../lib/glauco/framework/warble_shared"

module Glauco
  module Packaging
    module WarbleShared
      module_function

      def apply(config, executable:, includes:)
        Glauco::Framework::WarbleShared.apply(
          config,
          project_root: Dir.pwd,
          executable: executable,
          includes: includes
        )
      end
    end
  end
end
