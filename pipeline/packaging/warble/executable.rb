require_relative "shared"

Warbler::Config.new do |config|
  Glauco::Packaging::WarbleShared.apply(
    config,
    executable: "bin/main.rb",
    includes: [
      "public/carbon.js",
      "bin/main.rb"
    ]
  )

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
