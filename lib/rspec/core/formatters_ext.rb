require 'rspec/core/formatters'

module RSpec::Core::Formatters
  class ExceptionPresenter
    def fully_formatted_lines(failure_number, colorizer)
      [
        detail_formatter.call(example, colorizer),
        formatted_message_and_backtrace(colorizer),
        extra_detail_formatter.call(failure_number, colorizer)
      ].compact.flatten.map { |line| "#{' ' * (2 + @indentation)}#{line}" }
    end
  end

  class Loader
    def duplicate_formatter_exists?(new_formatter)
      @formatters.any? do |formatter|
        formatter.class == new_formatter.class &&
          (formatter.output == new_formatter.output ||
            formatter.class == RSpec::MultiprocessRunner::ReportingFormatter)
      end
    end
  end
end
