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

    def initialize(files, options={})
      @spec_files = []
      @results = Set.new
      @threads = []
      @failed_workers = []
      @spec_files_reference = files.to_set
      @hostname = options[:hostname]
      @port = options[:port]
      @max_threads = options[:max_slaves]
      @master = options[:master]
      if @master
        @spec_files = options[:use_given_order] ? files : sort_files(files)
        Thread.start { run_tcp_server }
        @slave_socket, master_socket = Socket.pair(:UNIX, :STREAM)
        Thread.start { server_connection_established(master_socket) }
      else
        count = 100
        while @slave_socket.nil? do
          begin
            @slave_socket = TCPSocket.new @hostname, @port
          rescue
            raise if count < 0
            count -= 1
            sleep(6)
          end
        end
      end
      ObjectSpace.define_finalizer( self, proc { @slave_socket.close } )
    end

    def remaining_files
      @spec_files
    end

    def missing_files
      if @master
        @spec_files_reference - @results.map(&:file_path) - @failed_workers.map(&:current_file)
      else
        []
      end
    end

    def get_file
      begin
        @slave_socket.puts [COMMAND_FILE].to_json
        file = @slave_socket.gets.chomp
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
      @slave_socket.puts [COMMAND_RESULTS, results].to_json
    end

    def send_worker_status(worker)
      @slave_socket.puts [COMMAND_PROCESS, worker, Socket.gethostname].to_json
    end

    def finished
      if @master
        @threads.each(&:join)
        @spec_files += missing_files.to_a
      else
        @slave_socket.puts [COMMAND_FINISHED].to_json
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
      ObjectSpace.define_finalizer( self, proc { server.close } )
      while @threads.size < @max_threads
        @threads << Thread.start(server.accept) do |client|
          server_connection_established(client)
        end
      end
    end

    def server_connection_established(socket)
      loop do
        raw_response = socket.gets
        break unless raw_response
        response = JSON.parse(raw_response)
        if response[0] == COMMAND_RESULTS && results = response[1].map { |result|
          ExampleResult.from_json_parse(result) }
          @results += results
        elsif response[0] == COMMAND_PROCESS && response[1]
          @failed_workers << MockWorker.from_json_parse(response[1], response[2] || unknown)
        elsif response[0] == COMMAND_FILE
          socket.puts @spec_files.shift
        elsif response[0] == COMMAND_FINISHED
          break
        end
      end
    end

    def work_left_to_do?
      !@spec_files.empty?
    end
  end
end
