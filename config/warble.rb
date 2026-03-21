Warbler::Config.new do |config|
  config.jar_name = "image_viewer"
  config.jar_extension = "jar"

  config.dirs = [
    "public",
    "node_modules",
    "examples",
    "glauco-framework",
    "glauco",
    "jarlibs",
    "bin"
  ]

  config.includes = [
    "carbon.js",
    "main.rb"
  ]

  config.excludes = [
    "node_modules/.bin",
    "node_modules/**/*.map"
  ]

  config.executable = "bin/main.rb"
  config.features = ["executable"]

  config.gem_excludes = [
    %r{(^|/)spec(/|$)},
    %r{(^|/)test(/|$)},
    %r{(^|/)examples(/|$)},
    %r{(^|/)doc(/|$)},
    %r{(^|/)docs(/|$)},
    %r{(^|/)benchmark(/|$)}
  ]

  config.java_libs += Dir.glob("jarlibs/*.jar")

  config.gem_dependencies = true
  config.gems += ["ruby_llm", "webrick"]
  config.bundler = false
end