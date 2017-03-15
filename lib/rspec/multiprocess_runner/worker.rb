# encoding: utf-8
require "rspec/multiprocess_runner"
require "rspec/multiprocess_runner/reporting_formatter"

require "rspec/core"
require "rspec/core/runner"

require "socket"
require "json"
require "timeout"
require "time"

module RSpec::MultiprocessRunner
  ##
  # This object has several roles:
  # - It forks the worker process
  # - In the coordinator process, it is used to send messages to the worker and
  #   track the worker's status, completed specs, and example results.
  # - In the worker process, it is used to send messages to the coordinator and
  #   actually run specs.
  #
  # @private
  class Worker
    attr_reader :pid, :environment_number, :example_results, :current_file
    attr_accessor :deactivation_reason

    COMMAND_QUIT = "quit"
    COMMAND_RUN_FILE = "run_file"

    STATUS_EXAMPLE_COMPLETE = "example_complete"
    STATUS_RUN_COMPLETE = "run_complete"

    def initialize(environment_number, options)
      @environment_number = environment_number
      @worker_socket, @coordinator_socket = Socket.pair(:UNIX, :STREAM)
      @rspec_arguments = (options[:rspec_options] || []) + ["--format", ReportingFormatter.to_s]
      @example_timeout_seconds = options[:example_timeout_seconds]
      @file_timeout_seconds = options[:file_timeout_seconds]
      @test_env_number_first_is_1 = options[:test_env_number_first_is_1]
      @example_results = []
    end

    ##
    # Workers can be found in the coordinator process by their coordinator socket.
    def ==(other)
      case other
      when Socket
        other == @coordinator_socket
      else
        super
      end
    end

    def test_env_number
      if environment_number == 1 && !@test_env_number_first_is_1
        ""
      else
        environment_number.to_s
      end
    end

    ##
    # Forks the worker process. In the parent, returns the PID.
    def start
      pid = fork
      if pid
        @worker_socket.close
        @pid = pid
      else
        @coordinator_socket.close
        @pid = Process.pid
        ENV["TEST_ENV_NUMBER"] = test_env_number

        # reset TERM handler so that
        # - the coordinator's version (if any) is not executed twice
        # - it actually terminates the process, instead of doing the ruby
        #   default (throw an exception, which gets caught by RSpec)
        Kernel.trap("TERM", "SYSTEM_DEFAULT")
        # rely on the coordinator to handle INT
        Kernel.trap("INT", "IGNORE")
        # prevent RSpec from trapping INT, also
        ::RSpec::Core::Runner.instance_eval { def self.trap_interrupt; end }

        # Disable RSpec's at_exit hook that would try to run whatever is in ARGV
        ::RSpec::Core::Runner.disable_autorun!

        set_process_name
        run_loop
      end
    end

    def socket
      if self.pid == Process.pid
        @worker_socket
      else
        @coordinator_socket
      end
    end

    ###### COORDINATOR METHODS
    ## These are methods that the coordinator process calls on its copy of
    ## the workers.

    public

    def quit_when_idle_and_wait_for_quit
      send_message_to_worker(command: COMMAND_QUIT)
      Process.wait(self.pid)
    end

    def run_file(filename)
      send_message_to_worker(command: COMMAND_RUN_FILE, filename: filename)
      @current_file = filename
      @current_file_started_at = @current_example_started_at = Time.now
    end

    def working?
      @current_file
    end

    def stalled?
      file_stalled =
        if @file_timeout_seconds
          working? && (Time.now - @current_file_started_at > @file_timeout_seconds)
        end
      example_stalled =
        if @example_timeout_seconds
          working? && (Time.now - @current_example_started_at > @example_timeout_seconds)
        end
      file_stalled || example_stalled
    end

    def shutdown_now
      terminate_then_kill(5)
    end

    def kill_now
      Process.kill(:KILL, pid)
      Process.detach(pid)
    end

    def reap
      terminate_then_kill(3, "Reaping troubled process #{environment_number} (#{pid}; #{@current_file})")
    end

    def receive_and_act_on_message_from_worker
      act_on_message_from_worker(receive_message_from_worker)
    end

    def to_json(options = nil)
      { "pid" => @pid, "environment_number" => @environment_number, "current_file" => @current_file, "deactivation_reason" => @deactivation_reason }.to_json
    end

    private

    def terminate_then_kill(timeout, message=nil)
      begin
        Timeout.timeout(timeout) do
          $stderr.puts "#{message} with TERM" if message
          if pid
            Process.kill(:TERM, pid)
            Process.wait(pid)
          end
        end
      rescue Timeout::Error
        $stderr.puts "#{message} with KILL" if message
        kill_now
      end
    end

    def receive_message_from_worker
      receive_message(@coordinator_socket)
    end

    def act_on_message_from_worker(message_hash)
      return :dead unless message_hash # ignore EOF
      case message_hash["status"]
      when STATUS_RUN_COMPLETE
        example_results << Result.new(message_hash)
        @current_file = nil
        @current_file_started_at = nil
        @current_example_started_at = nil
      when STATUS_EXAMPLE_COMPLETE
        example_results << Result.new(message_hash)
        suffix =
          case message_hash["example_status"]
          when "failed"
            " - FAILED"
          when "pending"
            " - pending"
          end
        if message_hash["details"]
          suffix += "\n#{message_hash["details"]}"
        end
        location = @current_file
        if message_hash["line_number"]
          location = [location, message_hash["line_number"]].join(':')
        end
        $stdout.puts "#{environment_number} (#{pid}): #{message_hash["description"]} (#{location})#{suffix}"
        @current_example_started_at = Time.now
      else
        $stderr.puts "Received unsupported status #{message_hash["status"].inspect} in worker #{pid}"
      end
      return :alive
    end

    def send_message_to_worker(message_hash)
      send_message(@coordinator_socket, message_hash)
    end

    ###### WORKER METHODS
    ## These are methods that the worker process calls on the copy of this
    ## object that lives in the fork.

    public

    def report_example_result(example_status, description, line_number, details)
      send_message_to_coordinator(
        status: STATUS_EXAMPLE_COMPLETE,
        example_status: example_status,
        description: description,
        line_number: line_number,
        details: details,
        filename: @current_file
      )
    end

    private

    def set_process_name
      name = "RSpec::MultiprocessRunner::Worker #{environment_number}"
      status = current_file ? "running #{current_file}" : "idle"
      $0 = "#{name} #{status}"
    end

    def run_loop
      loop do
        select_result = IO.select([@worker_socket], nil, nil, 1)
        if select_result
          readables, _, _ = select_result
          act_on_message_from_coordinator(
            receive_message_from_coordinator(readables.first)
          )
        end
      end
    end

    def handle_closed_coordinator_socket
      # when the coordinator socket is closed, there's nothing more to do
      exit
    end

    def receive_message_from_coordinator(socket)
      receive_message(socket)
    end

    def send_message_to_coordinator(message_hash)
      begin
        send_message(@worker_socket, message_hash)
      rescue Errno::EPIPE
        handle_closed_coordinator_socket
      end
    end

    def act_on_message_from_coordinator(message_hash)
      return handle_closed_coordinator_socket unless message_hash # EOF
      case message_hash["command"]
      when "quit"
        exit
      when "run_file"
        execute_spec(message_hash["filename"])
      else
        $stderr.puts "Received unsupported command #{message_hash["command"].inspect} in worker #{pid}"
      end
      set_process_name
    end

    def execute_spec(spec_file)
      @current_file = spec_file
      set_process_name

      # If we don't do this, every previous spec is run every time run is called
      RSpec.world.example_groups.clear

      ReportingFormatter.worker = self
      RSpec::Core::Runner.run(@rspec_arguments + [spec_file])
      send_message_to_coordinator(status: STATUS_RUN_COMPLETE, filename: spec_file)
    ensure
      @current_file = nil
    end

    ###### UTILITY FUNCTIONS
    ## Methods that used by both the coordinator and worker processes.

    private

    def receive_message(socket)
      message_json = socket.gets
      if message_json
        JSON.parse(message_json)
      end
    end

    def send_message(socket, message_hash)
      socket.puts(message_hash.to_json)
    end
  end

  class MockWorker
    attr_reader :pid, :environment_number, :current_file, :deactivation_reason, :node

    def initialize(hash, node)
      @pid = hash["pid"]
      @environment_number = hash["environment_number"]
      @current_file = hash["current_file"]
      @deactivation_reason = hash["deactivation_reason"]
      @node = node
    end

    def self.from_json_parse(hash, node)
      MockWorker.new(hash, node)
    end
  end

  # @private
  class Result
    attr_reader :run_status, :status, :description, :details, :filename, :time_finished

    def initialize(complete_message, time = Time.now)
      @hash = complete_message
      @run_status = complete_message["status"]
      @status = complete_message["example_status"]
      @description = complete_message["description"]
      @details = complete_message["details"]
      @filename = complete_message["filename"]
      @time_finished = time
    end

    def to_json(options = nil)
      { hash: @hash, time: @time_finished.iso8601(9) }.to_json
    end

    def self.from_json_parse(hash)
      Result.new(hash["hash"], Time.iso8601(hash["time"]))
    end
  end
end
