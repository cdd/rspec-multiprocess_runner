require 'spec_helper'
require 'timeout'

describe 'Exit code' do
  let(:executable) { 'ruby -Ilib exe/multirspec' }
  let(:args)       { '--worker-count=1' }
  let(:files)      { 'spec/files/successful.rb' }

  let(:command) do
    "#{executable} #{args} #{files}"
  end

  subject(:exit_code) do
    Process.wait spawn(command, %i(out err) => '/dev/null')
    $?.exitstatus
  end

  context 'on success' do
    let(:files) { 'spec/files/successful.rb' }

    it { is_expected.to eq(0) }
  end

  context 'on failing specs' do
    let(:files) { 'spec/files/failing.rb' }

    it { is_expected.to eq(1) }
  end

  context 'on broken followed by success' do
    let(:files) { 'spec/files/valid_but_broken.rb spec/files/successful.rb' }

    it { is_expected.to eq(2) }
  end

  context 'on success followed by broken' do
    let(:files) { 'spec/files/successful.rb spec/files/valid_but_broken.rb' }

    it { is_expected.to eq(2) }
  end

  context 'on process failures' do
    let(:files) { 'spec/files/syntax_error.rb' }

    it { is_expected.to eq(2) }
  end

  context 'if there are spec files that did not get run' do
    let(:args)  { '--worker-count=0' }
    let(:files) { 'spec/files/successful.rb' }

    it { is_expected.to eq(4) }
  end

  context 'on all of the failure scenarios' do
    it 'should eq 7' do
      pending 'not sure how to set this up'
      expect(exit_code).to eq(7)
    end
  end

  context 'on invalid arguments' do
    let(:args) { '--bad-args' }

    it { is_expected.to eq(64) }
  end

  def run_and_wait_for_workers(command, &block)
    read, write = IO.pipe
    pid = spawn(command, %i(out err) => write)

    Timeout::timeout(5) do
      loop do
        line = read.readline
        break if line =~ /starting worker/
      end

      block.call(pid)
      Process.wait(pid)
    end
  end

  context 'when sent SIGINT' do
    let(:files) { 'spec/files/very_slow.rb' }

    it 'should eq 65' do
      run_and_wait_for_workers(command) { |pid| Process.kill('INT', pid) }
      expect($?.exitstatus).to eq(65)
    end
  end

  context 'when sent SIGTERM' do
    let(:files) { 'spec/files/very_slow.rb' }

    it 'should eq 66' do
      run_and_wait_for_workers(command) { |pid| Process.kill('TERM', pid) }
      expect($?.exitstatus).to eq(66)
    end
  end

  context 'on a generic exception' do
    it 'should eq 67' do
      pending 'not sure how to set this up'
      expect(exit_code).to eq(67)
    end
  end
end
