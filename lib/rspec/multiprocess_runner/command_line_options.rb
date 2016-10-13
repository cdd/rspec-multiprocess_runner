require 'rspec/multiprocess_runner'
require 'optparse'
require 'pathname'

module RSpec::MultiprocessRunner
  # @private
  class CommandLineOptions
    attr_accessor :worker_count, :file_timeout_seconds, :example_timeout_seconds,
      :rspec_options, :explicit_files_or_directories, :pattern, :log_failing_files,
      :first_is_1, :use_given_order, :port, :head_node, :hostname, :max_nodes,
      :unique_string

    DEFAULT_WORKER_COUNT = 3

    def initialize
      self.worker_count = default_worker_count
      self.file_timeout_seconds = nil
      self.example_timeout_seconds = 15
      self.pattern = "**/*_spec.rb"
      self.log_failing_files = nil
      self.rspec_options = []
      self.first_is_1 = default_first_is_1
      self.use_given_order = false
      self.port = 2222
      self.hostname = "localhost"
      self.head_node = true
      self.max_nodes = 5
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
      end
    end

    private

    def default_worker_count
      from_env = ENV['MULTIRSPEC_WORKER_COUNT'] || ENV['PARALLEL_TEST_PROCESSORS']
      if from_env
        from_env.to_i
      else
        DEFAULT_WORKER_COUNT
      end
    end

    def default_first_is_1
      from_env = ENV['MULTIRSPEC_FIRST_IS_1'] || ENV['PARALLEL_TEST_FIRST_IS_1']
      %w(true 1).include?(from_env)
    end

    def help_requested!
      @help_requested = true
    end

    def help_requested?
      @help_requested
    end

    def print_default(default_value)
      if default_value
        "default: #{default_value}"
      else
        "none by default"
      end
    end

    def build_parser
      OptionParser.new do |parser|
        parser.banner = "#{File.basename $0} [options] [files or directories] [-- rspec options]"

        parser.on("-w", "--worker-count COUNT", Integer, "Number of workers to run (#{print_default worker_count})") do |n|
          self.worker_count = n
        end

        parser.on("-t", "--file-timeout SECONDS", Float, "Maximum time to allow any single file to run (#{print_default file_timeout_seconds})") do |s|
          self.file_timeout_seconds = s
        end

        parser.on("-T", "--example-timeout SECONDS", Float, "Maximum time to allow any single example to run (#{print_default example_timeout_seconds})") do |s|
          self.example_timeout_seconds = s
        end

        parser.on("-P", "--pattern PATTERN", "A glob to use to select files to run (#{print_default pattern})") do |pattern|
          self.pattern = pattern
        end

        parser.on("--log-failing-files FILENAME", "Filename to log failing files to") do |filename|
          self.log_failing_files = filename
        end

        parser.on("--first-is-1", "Use \"1\" for the first worker's TEST_ENV_NUMBER (instead of \"\")#{" (enabled in environment)" if first_is_1}") do
          self.first_is_1 = true
        end

        parser.on("-O", "--use-given-order", "Use the order that the files are given as arguments") do
          self.use_given_order = true
        end

        parser.on("-p", "--port PORT", Integer, "Communicate using port (#{print_default port})") do |port|
          self.port = port
        end

        parser.on("-H", "--hostname HOSTNAME", "Hostname of the head node (#{print_default hostname})") do |hostname|
          self.hostname = hostname
        end

        parser.on("-n", "--node", "This node is controlled by a head node") do
          self.head_node = false
        end

        parser.on("-m", "--max-nodes MAX_NODES", Integer, "Maximum number of nodes (excluding master) permitted (#{print_default max_nodes})") do |max_nodes|
          self.max_nodes = max_nodes
        end

        parser.on("-u", "--unique-string STRING", "A unique string used by nodes to confirm identity") do |string|
          self.unique_string = string
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
