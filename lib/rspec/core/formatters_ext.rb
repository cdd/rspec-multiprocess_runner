require 'rspec/core/formatters'

module RSpec::Core::Formatters
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
