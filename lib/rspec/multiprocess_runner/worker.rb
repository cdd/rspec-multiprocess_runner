# encoding: utf-8
require "rspec/multiprocess_runner"
require "rspec/multiprocess_runner/reporting_formatter"

require "rspec/core"
require "rspec/core/runner"

require "socket"
require "json"
require "timeout"

module RSpec::MultiprocessRunner
  ##
  # This object has several roles:
  # - It forks the worker process
  # - In the coordinator process, it is used to send messages to the worker and
  #   track the worker's status, completed specs, and example results.
  # - In the worker process, it is used to send messages to the coordinator and
  #   actually run specs.
  class Worker
    attr_reader :pid, :environment_number, :example_results, :current_file
    attr_accessor :deactivation_reason

    COMMAND_QUIT = "quit"
    COMMAND_RUN_FILE = "run_file"

    STATUS_EXAMPLE_COMPLETE = "example_complete"
    STATUS_RUN_COMPLETE = "run_complete"

    def initialize(environment_number, file_timeout, rspec_arguments=[])
      @environment_number = environment_number
      @worker_socket, @coordinator_socket = Socket.pair(:UNIX, :DGRAM, PROTOCOL_VERSION)
      @rspec_arguments = rspec_arguments + ["--format", ReportingFormatter.to_s]
      @file_timeout = file_timeout
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
        ENV["TEST_ENV_NUMBER"] = environment_number.to_s
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

    def quit
      send_message_to_worker(command: COMMAND_QUIT)
    end

    def wait_until_quit
      Process.wait(self.pid)
    end

    def run_file(filename)
      send_message_to_worker(command: COMMAND_RUN_FILE, filename: filename)
      @current_file = filename
      @current_file_started_at = Time.now
    end

    def working?
      @current_file
    end

    def stalled?
      working? && (Time.now - @current_file_started_at > @file_timeout)
    end

    def reap
      begin
        Timeout.timeout(4) do
          $stderr.puts "Reaping troubled process #{environment_number} (#{pid}; #{@current_file}) with QUIT"
          Process.kill(:QUIT, pid)
          Process.wait(pid)
        end
      rescue Timeout::Error
        $stderr.puts "Reaping troubled process #{environment_number} (#{pid}) with KILL"
        Process.kill(:KILL, pid)
        Process.wait(pid)
      end
    end

    def receive_and_act_on_message_from_worker
      act_on_message_from_worker(receive_message_from_worker)
    end

    private

    def receive_message_from_worker
      receive_message(@coordinator_socket)
    end

    def act_on_message_from_worker(message_hash)
      case message_hash["status"]
      when STATUS_RUN_COMPLETE
        @current_file = nil
        @current_file_started_at = nil
      when STATUS_EXAMPLE_COMPLETE
        example_results << ExampleResult.new(message_hash)
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
        $stdout.puts "#{environment_number} (#{pid}): #{message_hash["description"]}#{suffix}"
      else
        $stderr.puts "Received unsupported status #{message_hash["status"].inspect} in worker #{pid}"
      end
    end

    def send_message_to_worker(message_hash)
      send_message(@coordinator_socket, message_hash)
    end

    ###### WORKER METHODS
    ## These are methods that the worker process calls on the copy of this
    ## object that lives in the fork.

    public

    def report_example_result(example_status, description, details)
      send_message_to_coordinator(
        status: STATUS_EXAMPLE_COMPLETE,
        example_status: example_status,
        description: description,
        details: details
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

    def receive_message_from_coordinator(socket)
      receive_message(socket)
    end

    def send_message_to_coordinator(message_hash)
      send_message(@worker_socket, message_hash)
    end

    def act_on_message_from_coordinator(message_hash)
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
      message_json = socket.recv(MESSAGE_MAX_LENGTH, PROTOCOL_VERSION)
      JSON.parse(message_json)
    end

    def send_message(socket, message_hash)
      socket.send(message_hash.to_json, PROTOCOL_VERSION)
    end
  end

  # @private
  class ExampleResult
    attr_reader :status, :description, :details, :time_finished

    def initialize(example_complete_message)
      @status = example_complete_message["example_status"]
      @description = example_complete_message["description"]
      @details = example_complete_message["details"]
      @time_finished = Time.now
    end
  end
end
