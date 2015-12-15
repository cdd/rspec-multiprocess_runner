# encoding: utf-8

require 'spec_helper'
require 'rspec/multiprocess_runner/reporting_formatter'

describe RSpec::MultiprocessRunner::ReportingFormatter do
  let(:worker) { double('worker') }
  let(:output) { StringIO.new }
  let(:formatter) { RSpec::MultiprocessRunner::ReportingFormatter.new(output) }

  before(:each) do
    allow(worker).to receive(:report_example_result).and_return(nil)
    RSpec::MultiprocessRunner::ReportingFormatter.worker = worker
  end

  after(:each) do
    # Nothing should ever write to the output that's passed to the constructor
    expect(output.string).to eq("")
  end

  describe "when an example passes" do
    let(:group) {
      RSpec::Core::ExampleGroup.describe("example group") do
        describe "with details" do
          it("passes") { expect(2 + 2).to eq(4) }
        end
      end
    }

    before do
      group.run(formatter)
    end

    it "reports the pass to the worker" do
      expect(worker).to have_received(:report_example_result).with(:passed, "example group·with details·passes", anything)
    end
  end

  describe "when an example fails" do
    let(:group) {
      RSpec::Core::ExampleGroup.describe("example group") do
        describe "with details" do
          it("fails") { expect(2 + 2).to eq(5) }
        end
      end
    }

    before do
      group.run(formatter)
    end

    it "reports the failure to the worker" do
      expect(worker).to have_received(:report_example_result).with(:failed, "example group·with details·fails", anything)
    end

    it "sends the formatted details also" do
      expect(worker).to have_received(:report_example_result).with(
        :failed, anything,
        /Failure\/Error:.*2 \+ 2.*5/
      )
    end
  end

  describe "when an example is pending" do
    let(:group) {
      RSpec::Core::ExampleGroup.describe("example group") do
        describe "with details" do
          it "is not implemented yet"
        end
      end
    }

    before do
      group.run(formatter)
    end

    it "reports the pending example to the worker" do
      expect(worker).to have_received(:report_example_result).with(:pending, "example group·with details·is not implemented yet", anything)
    end

    it "sends the formatted details also" do
      expect(worker).to have_received(:report_example_result).with(
        :pending, anything,
        /not implemented/
      )
    end
  end
end
