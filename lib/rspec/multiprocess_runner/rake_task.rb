require 'rspec/multiprocess_runner'
require 'rake'
require 'rake/tasklib'
require 'shellwords'

module RSpec::MultiprocessRunner
  # Rake task to invoke `multispec`. Lots of it is copied from RSpec::Core::RakeTask.
  #
  # @see Rakefile
  class RakeTask < ::Rake::TaskLib
    include ::Rake::DSL if defined?(::Rake::DSL)

    # Default path to the multirspec executable.
    DEFAULT_MULTIRSPEC_PATH = File.expand_path('../../../../exe/multirspec', __FILE__)

    # Name of task. Defaults to `:multispec`.
    attr_accessor :name

    # Files matching this pattern will be loaded.
    # Defaults to `'**/*_spec.rb'`.
    attr_accessor :pattern

    # File search will be limited to these directories or specific files.
    # Defaults to nil.
    attr_accessor :files_or_directories
    alias_method :files=, :files_or_directories=
    alias_method :directories=, :files_or_directories=

    # The number of workers to run. Defaults to 3.
    attr_accessor :worker_count

    # The maximum number of seconds to allow a single spec file to run
    # before killing it. Defaults to disabled.
    attr_accessor :file_timeout_seconds

    # The maximum number of seconds to allow a single example to run
    # before killing it. Defaults to 15.
    attr_accessor :example_timeout_seconds

    # Whether or not to fail Rake when an error occurs (typically when
    # examples fail). Defaults to `true`.
    attr_accessor :fail_on_error

    # A message to print to stderr when there are failures.
    attr_accessor :failure_message

    # Use verbose output. If this is set to true, the task will print the
    # executed spec command to stdout. Defaults to `true`.
    attr_accessor :verbose

    # Path to the multispec executable. Defaults to the absolute path to the
    # rspec binary from the loaded rspec-core gem.
    attr_accessor :multirspec_path

    # Filename to which to append a list of the files containing specs that
    # failed.
    attr_accessor :log_failing_files

    # Command line options to pass to the RSpec workers. Defaults to `nil`.
    attr_accessor :rspec_opts

    def initialize(*args, &task_block)
      @name            = args.shift || :multispec
      @verbose         = true
      @fail_on_error   = true
      @multirspec_path = DEFAULT_MULTIRSPEC_PATH

      define(args, &task_block)
    end

    # @private
    def run_task(verbose)
      command = spec_command
      puts Shellwords.shelljoin(command) if verbose

      return if system(*command)
      puts failure_message if failure_message

      return unless fail_on_error
      $stderr.puts "#{command} failed" if verbose
      exit $?.exitstatus
    end

    private

    # @private
    def define(args, &task_block)
      desc "Run RSpec code examples" unless ::Rake.application.last_comment

      task name, *args do |_, task_args|
        RakeFileUtils.__send__(:verbose, verbose) do
          task_block.call(*[self, task_args].slice(0, task_block.arity)) if task_block
          run_task verbose
        end
      end
    end

    def spec_command
      cmd_parts = []
      cmd_parts << RUBY
      cmd_parts << multirspec_path
      if worker_count
        cmd_parts << '--worker-count' << worker_count.to_s
      end
      if example_timeout_seconds
        cmd_parts << '--example-timeout' << example_timeout_seconds.to_s
      end
      if file_timeout_seconds
        cmd_parts << '--file-timeout' << file_timeout_seconds.to_s
      end
      if pattern
        cmd_parts << '--pattern' << pattern
      end
      if log_failing_files
        cmd_parts << '--log-failing-files' << log_failing_files
      end
      if files_or_directories
        cmd_parts.concat(files_or_directories)
      end
      if rspec_opts
        cmd_parts << '--'
        cmd_parts.concat(Shellwords.shellsplit rspec_opts)
      end

      cmd_parts
    end
  end
end
