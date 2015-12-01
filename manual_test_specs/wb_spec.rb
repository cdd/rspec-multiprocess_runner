require File.expand_path('../spec_helper', __FILE__)

describe 'wb' do
  it 'works' do
    # Tests that the config from spec_helper remains available across runs
    expect(test_sum(3, 6)).to eq(9)
  end
end
