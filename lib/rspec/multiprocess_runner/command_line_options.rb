require 'rspec/multiprocess_runner'
require 'optparse'
require 'pathname'

module RSpec::MultiprocessRunner
  # @private
  class CommandLineOptions
    attr_accessor :process_count, :file_timeout_seconds, :rspec_options,
      :explicit_files_or_directories, :pattern

    def initialize
      self.process_count = 3
      self.file_timeout_seconds = 300
      self.pattern = "**/*_spec.rb"
      self.rspec_options = []
    end

    def parse(command_line_args, error_stream=$stderr)
      args = command_line_args.dup
      parser = build_parser

      begin
        parser.parse!(args)
      rescue OptionParser::ParseError => e
        error_stream.puts e.to_s
        error_stream.puts parser
        return nil
      end

      if help_requested?
        error_stream.puts parser
        return nil
      end

      extract_files_and_rspec_options(args)
      self
    end

    def files_to_run
      self.explicit_files_or_directories = %w(.) unless explicit_files_or_directories
      relative_root = Pathname.new('.')
      explicit_files_or_directories.map { |path| Pathname.new(path) }.flat_map do |path|
        if path.file?
          path.to_s
        else
          Dir[path.join(pattern).relative_path_from(relative_root)]
        end
      end.sort_by { |path| path.downcase }
    end

    private

    def help_requested!
      @help_requested = true
    end

    def help_requested?
      @help_requested
    end

    def build_parser
      OptionParser.new do |parser|
        parser.banner = "#{File.basename $0} [options] [files or directories] [-- rspec options]"

        parser.on("-c", "--process-count COUNT", Integer, "Number of processes to run (default: #{process_count})") do |n|
          self.process_count = n
        end

        parser.on("-t", "--file-timeout SECONDS", Integer, "Maximum time to allow any single file to run (default: #{file_timeout_seconds})") do |s|
          self.file_timeout_seconds = s
        end

        parser.on("-P", "--pattern PATTERN", "A glob to use to select files to run (default: #{pattern})") do |pattern|
          self.pattern = pattern
        end

        parser.on_tail("-h", "--help", "Prints this help") do
          help_requested!
        end
      end
    end

    def extract_files_and_rspec_options(remaining_args)
      files = []
      rspec_options = []
      target = files
      remaining_args.each do |arg|
        if arg[0] == '-'
          target = rspec_options
        end
        target << arg
      end

      self.explicit_files_or_directories = files unless files.empty?
      self.rspec_options = rspec_options unless rspec_options.empty?
    end
  end
end
