require_relative "lib/glauco/framework/version"

Gem::Specification.new do |spec|
  spec.name          = "glauco-framework"
  spec.version       = Glauco::Framework::VERSION
  spec.authors       = ["Glauco"]
  spec.email         = ["devnull@example.com"]

  spec.summary       = "Desktop UI framework em JRuby com SWT e runtime reativo."
  spec.description   = "Framework local Glauco para construir aplicacoes desktop HTML com JRuby, SWT e componentes reativos."
  spec.homepage      = "https://example.invalid/glauco-framework"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir[
    "bin/*",
    "core/framework/**/*",
    "exe/*",
    "jarlibs/**/*",
    "lib/**/*",
    "pipeline/executables/bin/*",
    "public/**/*",
    "README.md"
  ].select { |path| File.file?(path) }
   .reject { |path| path.start_with?("core/framework/web/node_modules/") }

  spec.bindir = "exe"
  spec.executables = ["glauco-package"]
  spec.require_paths = ["lib"]

  spec.add_dependency "docx", "~> 0.10"
  spec.add_dependency "logger", "~> 1.7"
  spec.add_dependency "nodo", "~> 1.8"
  spec.add_dependency "observer", "~> 0.1"
  spec.add_dependency "pdf-reader", "~> 2.15"
  spec.add_dependency "roo", "~> 3.0"
  spec.add_dependency "ruby_llm", "~> 1.14"
  spec.add_dependency "rubyXL", "~> 3.4"
  spec.add_dependency "webrick", "~> 1.9"
end
