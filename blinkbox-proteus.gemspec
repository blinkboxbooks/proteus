# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "blinkbox-proteus"
  spec.version       = File.read("VERSION") rescue "0.0.0"
  spec.authors       = ["JP Hastings-Spital"]
  spec.email         = ["jphastings@blinkbox.com"]
  spec.summary       = %q{Build tool for automatic version management with github}
  spec.description   = %q{Build tool for automatic version management with github}
  spec.homepage      = "https://git.mobcastdev.com/Deployment/proteus#readme"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
end
