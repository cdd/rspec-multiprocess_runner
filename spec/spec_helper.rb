$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'rspec/multiprocess_runner'
require 'rspec/core'
require 'stub_env'

Dir['./spec/support/**/*.rb'].map {|f| require f}

# Copied from RSpec 2.14's spec_helper
module Sandboxing
  def self.sandboxed(&block)
    @orig_config = RSpec.configuration
    @orig_world  = RSpec.world
    new_config = RSpec::Core::Configuration.new
    new_world  = RSpec::Core::World.new(new_config)
    RSpec.configuration = new_config
    RSpec.world = new_world
    object = Object.new
    object.extend(RSpec::Core::SharedExampleGroup)

    (class << RSpec::Core::ExampleGroup; self; end).class_eval do
      alias_method :orig_run, :run
      def run(reporter=nil)
        orig_run(reporter || NullObject.new)
      end
    end

    RSpec::Core::SandboxedMockSpace.sandboxed do
      object.instance_eval(&block)
    end
  ensure
    (class << RSpec::Core::ExampleGroup; self; end).class_eval do
      remove_method :run
      alias_method :run, :orig_run
      remove_method :orig_run
    end

    RSpec.configuration = @orig_config
    RSpec.world = @orig_world
  end
end

RSpec.configure do |c|
  c.around {|example| Sandboxing.sandboxed { example.run }}
  c.include StubEnv::Helpers
end
