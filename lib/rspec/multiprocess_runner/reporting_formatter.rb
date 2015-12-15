# encoding: utf-8
require 'rspec/multiprocess_runner'
require 'rspec/core/formatters/base_text_formatter'

module RSpec::MultiprocessRunner
  ##
  # RSpec formatter used by workers to communicate spec execution to the
  # coordinator.
  #
  # @private
  class ReportingFormatter < RSpec::Core::Formatters::BaseTextFormatter
    class << self
      # The worker to which to report spec status. This has to be a class-level
      # attribute because you can't access the formatter instance used by
      # RSpec's runner.
      attr_accessor :worker
    end

    def initialize(*ignored_args)
      super(StringIO.new)
      @current_example_groups = []
    end

    def example_group_started(example_group)
      super(example_group)

      @current_example_groups.push(example_group.description.strip)
    end

    def example_group_finished(example_group)
      @current_example_groups.pop
    end

    def example_passed(example)
      super(example)
      report_example_result(:passed, current_example_description(example))
    end

    def example_pending(example)
      super(example)
      details = capture_output { dump_pending }
      pending_examples.clear
      report_example_result(:pending, current_example_description(example), details)
    end

    def example_failed(example)
      super(example)
      details = capture_output {
        dump_failure_info(example)
        dump_backtrace(example)
      }
      report_example_result(:failed, current_example_description(example), details)
    end

    private

    def capture_output
      output.string = ""
      yield
      captured = output.string
      output.string = ""
      captured
    end

    def worker
      self.class.worker
    end

    def current_example_description(example)
      (@current_example_groups + [example.description.strip]).join('·')
    end

    def report_example_result(example_status, description, details=nil)
      worker.report_example_result(example_status, description, details)
    end
  end
end
