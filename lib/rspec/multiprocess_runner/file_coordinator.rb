# encoding: utf-8
require 'rspec/multiprocess_runner'
require 'socket'
require 'pry'

module RSpec::MultiprocessRunner
  class FileCoordinator
    attr_reader :results

    COMMAND_FILE = "file"
    COMMAND_RESULTS = "results"
    COMMAND_FINISHED = "finished"

    def initialize(files, options={})
      @spec_files = []
      @results = []
      @threads = []
      @spec_files_reference = files.to_set
      @hostname = options[:hostname]
      @port = options[:port]
      @max_threads = options[:max_slaves]
      @master = options[:master]
      if @master
        @spec_files = options[:use_given_order] ? files : sort_files(files)
        Thread.start { run_server }
      end
      count = 100
      while @tcp_socket.nil? do
        begin
          @tcp_socket = TCPSocket.new @hostname, @port
        rescue
          raise if count < 0
          count--
          sleep(6)
        end
      end
      ObjectSpace.define_finalizer( self, proc { @tcp_socket.close } )
    end

    def remaining_files
      @spec_files
    end

    def missing_files
      if @master
        @spec_files_reference - @results.map(&:file_path)
      else
        []
      end
    end

    def get_file
      begin
        socket = @tcp_socket
        socket.puts [COMMAND_FILE].to_json
        file = socket.gets.chomp
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
      begin
        socket = @tcp_socket
        socket.puts [COMMAND_RESULTS, results].to_json
      rescue
      end
    end

    def finished
      @tcp_socket.puts [COMMAND_FINISHED].to_json
      @threads.each(&:join)
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

    def run_server
      server = TCPServer.new @port
      ObjectSpace.define_finalizer( self, proc { server.close } )
      while @threads.size < @max_threads
        @threads << Thread.start(server.accept) do |client|
          begin
            loop do
              response = JSON.parse(client.gets)
              if response[0] == COMMAND_RESULTS && results = response[1].map { |result|
                ExampleResult.from_json_parse(result) }
                @results += results
              elsif response[0] == COMMAND_FILE
                client.puts @spec_files.shift
              elsif response[0] == COMMAND_FINISHED
                break
              end
            end
          rescue
          end
          client.close
        end
      end
    end

    def work_left_to_do?
      !@spec_files.empty?
    end
  end
end
