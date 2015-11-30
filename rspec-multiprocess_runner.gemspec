# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rspec/multiprocess_runner/version'

Gem::Specification.new do |spec|
  spec.name          = "rspec-multiprocess_runner"
  spec.version       = Rspec::MultiprocessRunner::VERSION
  spec.authors       = ["Rhett Sutphin"]
  spec.email         = ["rhett@detailedbalance.net"]

  spec.summary       = %q{A runner for RSpec 2 that uses multiple processes to execute specs in parallel}
  spec.homepage      = "https://github.com/cdd/rspec-multiprocess_runner"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features|manual_test_specs)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec-core", "~> 2.0", "< 2.99.0"

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
end
