$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'rspec/multiprocess_runner'
require 'rspec/core/sandbox'
require 'stub_env'

Dir['./spec/support/**/*.rb'].map {|f| require f}

# Copied from RSpec 3.5
# Because testing RSpec with RSpec tries to modify the same global
# objects, we sandbox every test.
RSpec.configure do |c|
  c.around do |ex|
    RSpec::Core::Sandbox.sandboxed do |config|
      # If there is an example-within-an-example, we want to make sure the inner example
      # does not get a reference to the outer example (the real spec) if it calls
      # something like `pending`
      config.before(:context) { RSpec.current_example = nil }

      orig_load_path = $LOAD_PATH.dup

      ex.run
      $LOAD_PATH.replace(orig_load_path)
    end
  end

  c.include StubEnv::Helpers
end
