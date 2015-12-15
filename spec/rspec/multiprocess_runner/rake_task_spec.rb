require 'spec_helper'
require 'rspec/multiprocess_runner/rake_task'

# Some of these specs are copied from RSpec::Core::RakeTask's specs
module RSpec::MultiprocessRunner
  describe RakeTask do
    let(:task) { RakeTask.new }

    def ruby
      FileUtils::RUBY
    end

    def spec_command
      task.__send__(:spec_command)
    end

    RSpec::Matchers.define :include_elements_in_order do |*elements|
      match do |array|
        expected_elt_count = elements.size
        (0..(array.size - expected_elt_count)).detect do |i|
          array[i, expected_elt_count] == elements
        end
      end
    end

    context "with a name passed to the constructor" do
      let(:task) { RakeTask.new(:task_name) }

      it "correctly sets the name" do
        expect(task.name).to eq :task_name
      end
    end

    context "with args passed to the rake task" do
      it "correctly passes along task arguments" do
        the_task = RakeTask.new(:rake_task_args, :files) do |t, args|
          expect(args[:files]).to eq "spec/jobs"
        end

        expect(the_task).to receive(:run_task) { true }
        expect(Rake.application.invoke_task("rake_task_args[spec/jobs]")).not_to be_nil
      end
    end

    context "default" do
      it "executes multispec" do
        expect(spec_command).to include_elements_in_order(ruby, task.multirspec_path)
      end
    end

    context "with rspec_opts" do
      it "adds the rspec_opts to the end of the command, after --" do
        task.rspec_opts = "-Ifoo -r 'bar helpers.rb'"
        expect(spec_command).to include_elements_in_order("--", "-Ifoo", "-r", "bar helpers.rb")
      end
    end

    context "with a pattern" do
      it "is present in the command" do
        task.pattern = "yellow/**/*_spec.rb"
        expect(spec_command).to include_elements_in_order("--pattern", "yellow/**/*_spec.rb")
      end
    end

    context "with a worker count" do
      it "is passed into the command" do
        task.worker_count = 17
        expect(spec_command).to include_elements_in_order("--worker-count", "17")
      end
    end

    context "with a file timeout" do
      it "is passed into the command" do
        task.file_timeout_seconds = 79
        expect(spec_command).to include_elements_in_order("--file-timeout", "79")
      end
    end

    context "with explicit files" do
      it "includes them in the command" do
        task.files_or_directories = %w(spec/models/soul_spec.rb spec/actions/sale_spec.rb)
        expect(spec_command).to include("spec/models/soul_spec.rb", "spec/actions/sale_spec.rb")
      end
    end

    context "with everything" do
      it "has all the arguments in an order that will work" do
        task.pattern = "*.feature"
        task.directories = %w(features)
        task.worker_count = 8
        task.file_timeout_seconds = 600
        task.rspec_opts = "--backtrace"

        expect(spec_command).to eq([
          ruby,
          task.multirspec_path,
          "--worker-count", "8",
          "--file-timeout", "600",
          "--pattern", "*.feature",
          "features",
          "--",
          "--backtrace"
        ])
      end
    end
  end
end
