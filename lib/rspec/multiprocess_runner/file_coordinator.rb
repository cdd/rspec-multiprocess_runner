# encoding: utf-8
require 'rspec/multiprocess_runner'
require 'socket'

module RSpec::MultiprocessRunner
  class FileCoordinator
    attr_reader :results, :failed_workers

    COMMAND_FILE = "file"
    COMMAND_RESULTS = "results"
    COMMAND_PROCESS = "process"
    COMMAND_FINISHED = "finished"
    COMMAND_START = "start"

    def initialize(files, options={})
      @spec_files = []
      @results = Set.new
      @threads = []
      @failed_workers = []
      @spec_files_reference = files.to_set
      @hostname = options[:hostname]
      @port = options[:port]
      @max_threads = options[:max_nodes]
      @head_node = options[:head_node]
      @start_string = options[:run_identifier]
      if @head_node
        @spec_files = options[:use_given_order] ? files : sort_files(files)
        Thread.start { run_tcp_server }
        @node_socket, head_node_socket = Socket.pair(:UNIX, :STREAM)
        Thread.start { server_connection_established(head_node_socket) }
      else
        count = 100
        while @node_socket.nil? do
          begin
            @node_socket = TCPSocket.new @hostname, @port
            raise unless start?
          rescue BadStartStringError
            @node_socket.close if @node_socket
            raise
          rescue
            @node_socket.close if @node_socket
            @node_socket = nil
            raise if count < 0
            count -= 1
            sleep(6)
          end
        end
        puts
      end
      ObjectSpace.define_finalizer( self, proc { @node_socket.close } )
    end

    def remaining_files
      @spec_files
    end

    def missing_files
      if @head_node
        @spec_files_reference - @results.map(&:filename) - @failed_workers.map(&:current_file) - @spec_files
      else
        []
      end
    end

    def get_file
      begin
        @node_socket.puts [COMMAND_FILE].to_json
        file = @node_socket.gets.chomp
        if @spec_files_reference.include? file
          return file
        else
          return nil # Malformed response, assume done, cease function
        end
      rescue
        return nil # If Error, assume done, cease function
      end
    end

    def send_results(results)
      @node_socket.puts [COMMAND_RESULTS, results].to_json
    end

    def send_worker_status(worker)
      @node_socket.puts [COMMAND_PROCESS, worker, Socket.gethostname].to_json
    end

    def finished
      if @head_node
        if @tcp_server_running
         @tcp_server_running = false
         @threads.each(&:join)
         @spec_files += missing_files.to_a
        end
      else
        @node_socket.puts [COMMAND_FINISHED].to_json
      end
    end

    private

    # Sorting by decreasing size attempts to ensure we don't send the slowest
    # file to a worker right before all the other workers finish and then end up
    # waiting for that one process to finish.
    # In the future it would be nice to log execution time and sort by that.
    def sort_files(files)
      # #sort_by caches the File.size result so we only call it once per file.
      files.sort_by { |file| -File.size(file) }
    end

    def run_tcp_server
      server = TCPServer.new @port
      @tcp_server_running = true
      ObjectSpace.define_finalizer( self, proc { server.close } )
      while @threads.size < @max_threads && @tcp_server_running
        @threads << Thread.start(server.accept) do |client|
          server_connection_established(client) if @tcp_server_running
        end
      end
    end

    def server_connection_established(socket)
      loop do
        raw_response = socket.gets
        break unless raw_response
        command, results, node = JSON.parse(raw_response)
        if command == COMMAND_START
          if results == @start_string
            socket.puts COMMAND_START
          else
            socket.puts COMMAND_FINISHED
            break
          end
        elsif command == COMMAND_FILE
          socket.puts @spec_files.shift
        elsif command == COMMAND_PROCESS && results
          @failed_workers << MockWorker.from_json_parse(results, node || "unknown")
        elsif command == COMMAND_RESULTS && results = results.map { |result|
          Result.from_json_parse(result) }
          @results += results
        elsif command == COMMAND_FINISHED
          break
        end
      end
    end

    def start?
      begin
        @node_socket.puts [COMMAND_START, @start_string].to_json
        response = @node_socket.gets
        response = response.chomp if response
        raise BadStartStringError if response == COMMAND_FINISHED
        response == COMMAND_START
      rescue Errno::EPIPE
        false
      end
    end
  end

  class BadStartStringError < StandardError
    def initialize(msg="An incorrect unique string was passed by the head node.")
      super
    end
  end
end
