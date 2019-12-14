# encoding: utf-8
require_relative '../../spec_helper'
require 'rspec/multiprocess_runner/command_line_options'
require 'rspec/multiprocess_runner/file_coordinator'

describe RSpec::MultiprocessRunner::FileCoordinator do
  subject { described_class.new(files, options) }
  let(:files) { [] }
  let(:options) { RSpec::MultiprocessRunner::CommandLineOptions.new }
  describe '.initialize' do
    context 'as head node' do
      before do
        options.head_node = true
      end

      it 'should work' do
        expect { subject }.not_to raise_error
      end
    end

    context 'not as head node' do
      before do
        options.head_node = false
        head_node_socket = double('server').as_null_object
        allow(head_node_socket).to receive(:gets).and_return(described_class::COMMAND_START)
        allow(TCPSocket).to receive(:new).and_return(head_node_socket)
      end

      it 'should work' do
        expect { subject }.not_to raise_error
      end
    end
  end
end
