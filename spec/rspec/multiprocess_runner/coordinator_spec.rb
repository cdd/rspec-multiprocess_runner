# encoding: utf-8
require 'byebug'
require_relative '../../spec_helper'
require 'rspec/multiprocess_runner/coordinator'

describe RSpec::MultiprocessRunner::Coordinator do
  describe '.run' do
    let(:worker_count) { 1 }
    let(:files) { [] }
    let(:log_failing_files) { 'log_failing_files' }
    let(:options) { double('options', {head_node: true, use_given_order: true, worker_count: 1, summary_filename: nil, log_failing_files: 'log_failing_files'}) }
    let(:coordinator) { RSpec::MultiprocessRunner::Coordinator.new(worker_count, files, options) }

    around(:each) do |example|
      File.delete(log_failing_files) if File.exist?(log_failing_files)
      example.run
      File.delete(log_failing_files) if File.exist?(log_failing_files)
    end

    before(:each) do
      file_coordinator = double('FileCoordinator', {get_file: nil, finished: nil, remaining_files: [], results: [], missing_files: [], failed_workers: []} )
      allow(RSpec::MultiprocessRunner::FileCoordinator).to receive(:new) { file_coordinator }
    end

    it "should work" do
      expect(coordinator.run).to eq(0)
    end

    it "should work with a summary file" do
      string_file = StringIO.new
      expect(coordinator).to receive(:summary_file) { string_file }
      expect(coordinator.run).to eq(0)
      expect(string_file.string).to match(/0 examples/)
    end
  end
end
