require 'rspec'

module SomeTestMethods
  def test_sum(a, b)
    a + b
  end
end

RSpec.configure do |c|
  c.include SomeTestMethods
end
