require_relative "shared"

Warbler::Config.new do |config|
  Glauco::Packaging::WarbleShared.apply(
    config,
    executable: "examples/basic_ui_with_fs_io.rb",
    includes: [
      "public/carbon.js",
      "examples/basic_ui_with_fs_io.rb"
    ]
  )
end
