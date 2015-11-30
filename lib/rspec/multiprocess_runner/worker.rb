require "rspec/multiprocess_runner"
require "rspec/core/runner"
require "socket"
require "json"

module RSpec::MultiprocessRunner
  class Worker
    attr_reader :pid, :environment_number

    COMMAND_QUIT = "quit"
    COMMAND_RUN_FILE = "run_file"

    STATUS_RUN_COMPLETE = "complete"

    def initialize(environment_number, rspec_options)
      @environment_number = environment_number
      @worker_socket, @coordinator_socket = Socket.pair(:UNIX, :DGRAM, PROTOCOL_VERSION)
      @rspec_options = rspec_options
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
        $0 = "RSpec::MultiprocessRunner::Worker #{environment_number}"
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

    private

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
    end

    def execute_spec(spec_file)
      $stderr.puts "#{environment_number} (#{pid}): Here is where I would execute #{spec_file}"
      sleep(rand)
      send_message_to_coordinator(status: STATUS_RUN_COMPLETE, filename: spec_file)
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
end
