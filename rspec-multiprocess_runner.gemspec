# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rspec/multiprocess_runner/version'

Gem::Specification.new do |spec|
  spec.name          = "rspec-multiprocess_runner"
  spec.version       = RSpec::MultiprocessRunner::VERSION
  spec.authors       = ["Rhett Sutphin", 'Jacob Bloom', 'Peter Nyberg', 'Kurt Werle']
  spec.email         = ["kwerle@collaborativedrug.com"]

  spec.summary       = %q{A runner for RSpec 3 that uses multiple processes to execute specs in parallel}
  spec.homepage      = "https://github.com/cdd/rspec-multiprocess_runner"
  spec.license       = "MIT"

  spec.files         = Dir.glob('{bin,lib,exe}/**/*') + %w[ruby_language_server.gemspec Gemfile Gemfile.lock Rakefile CHANGELOG.md LICENSE.txt README.md TODO.md]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec", ">= 3.0"

  spec.add_development_dependency "bundler", ">= 1.10"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "stub_env"
end
