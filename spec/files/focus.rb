RSpec.configure do |config|
  config.filter_run focus: true
end

describe 'focus spec' do
  it 'should mention focus in a message' do
    expect(true).to be_truthy
  end
end
