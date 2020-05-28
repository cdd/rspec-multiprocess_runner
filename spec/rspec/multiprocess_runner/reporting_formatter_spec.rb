# encoding: utf-8

require 'spec_helper'
require 'rspec/multiprocess_runner/reporting_formatter'

describe RSpec::MultiprocessRunner::ReportingFormatter do
  let(:worker) { double('worker') }
  let(:output) { StringIO.new }
  let(:formatter) { RSpec::MultiprocessRunner::ReportingFormatter.new(output) }
  let(:reporter)  { RSpec::Core::Reporter.new(RSpec.configuration) }

  before(:each) do
    allow(worker).to receive(:report_example_result).and_return(nil)
    allow(worker).to receive(:report_error).and_return(nil)
    RSpec::MultiprocessRunner::ReportingFormatter.worker = worker

    reporter.register_listener formatter,
      :example_group_started,
      :example_group_finished,
      :example_passed,
      :example_pending,
      :example_failed
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
      group.run(reporter)
    end

    it "reports the pass to the worker" do
      # N.b.: the line number is in this actual file — it will change if you
      # insert anything above this example group
      expect(worker).to have_received(:report_example_result).
        with(:passed, "example group·with details·passes", 34, anything)
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
      group.run(reporter)
    end

    it "reports the failure to the worker" do
      # N.b.: the line number is in this actual file — it will change if you
      # insert anything above this example group
      expect(worker).to have_received(:report_example_result).
        with(:failed, "example group·with details·fails", 55, anything)
    end

    it "sends the formatted details also" do
      expect(worker).to have_received(:report_example_result).with(
        :failed, anything, anything,
        /Failure\/Error:/
      )
    end

    it "does not send an erroneous failure number" do
      # This regex checks that the string does not contain, or more precisely:
      # checks that every character, including newlines, is not preceded with
      # '1) example group`.
      expect(worker).to have_received(:report_example_result).with(
        :failed, anything, anything,
        /\A((?!1\) example group).)*\z/m
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
      group.run(reporter)
    end

    it "reports the pending example to the worker" do
      # N.b.: the line number is in this actual file — it will change if you
      # insert anything above this example group
      expect(worker).to have_received(:report_example_result).
        with(:pending, "example group·with details·is not implemented yet", 93, anything)
    end

    it "sends the formatted details also" do
      expect(worker).to have_received(:report_example_result).with(
        :pending, anything, anything,
        /not implemented/
      )
    end
  end

  describe "when it receives a message" do
    def subject(message, non_example_failure)
      RSpec.world.non_example_failure = non_example_failure
      formatter.message(Struct.new(:message).new(message))
    ensure
      RSpec.world.non_example_failure = false
    end

    context "and there was no error outside the specs" do
      it "does nothing" do
        subject("something innocuous", false)
        expect(worker).to_not have_received(:report_error)
      end
    end

    context "and there was an error outside the specs" do
      it "sends the worker the error" do
        subject("something erroneous", true)
        expect(worker).to have_received(:report_error).with("something erroneous")
      end

      it "does nothing if the message is about an empty file (these occur after errors)" do
        subject("No examples found.", true)
        expect(worker).to_not have_received(:report_error)
      end
    end
  end
end
