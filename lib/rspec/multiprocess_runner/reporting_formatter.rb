# encoding: utf-8
require 'rspec/multiprocess_runner'
require 'rspec/core'
require 'rspec/core/formatters/base_text_formatter'

module RSpec::MultiprocessRunner
  ##
  # RSpec formatter used by workers to communicate spec execution to the
  # coordinator.
  #
  # @private
  class ReportingFormatter < RSpec::Core::Formatters::DocumentationFormatter
    RSpec::Core::Formatters.register self,
      :example_group_started,
      :example_group_finished,
      :example_passed,
      :example_pending,
      :example_failed

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

    def example_group_started(notification)
      super(notification)

      @current_example_groups.push(notification.group.description.strip)
    end

    def example_group_finished(example_group)
      @current_example_groups.pop
    end

    def example_passed(notification)
      report_example_result(:passed, notification.example)
    end

    def example_pending(notification)
      details = capture_output { super(notification) }
      report_example_result(:pending, notification.example, details)
    end

    def example_failed(notification)
      details = capture_output { super(notification) }
      report_example_result(
        :failed,
        notification.example,
        notification.fully_formatted(1)
      )
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

    def report_example_result(example_status, example, details=nil)
      description = current_example_description(example)
      line = example.metadata[:line_number]
      worker.report_example_result(example_status, description, line, details)
    end
  end
end
