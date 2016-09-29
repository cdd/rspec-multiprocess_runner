# encoding: utf-8
require 'rspec/multiprocess_runner'
require 'socket'

module RSpec::MultiprocessRunner
  class FileCoordinator
    def initialize(files, options={})
      @spec_files = []
      @spec_files_reference = files.to_set
      @hostname = options[:hostname]
      @port = options[:port]
      if options[:master]
        @spec_files = options[:use_given_order] ? files : sort_files(files)
        Thread.start {run_server}
      end
    end

    def remaining_files
      @spec_files
    end

    def get_file
      begin
        socket = TCPSocket.new @hostname, @port
        file = socket.gets.strip
        socket.close
        if true || (@spec_files_reference.include? file)
          return file
        else
          return nil # Malformed response, assume done, cease function
        end
      rescue
        return nil # If Error, assume done, cease function
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


    def run_server
      server = TCPServer.new @port
      loop do
        Thread.start(server.accept) do |client|
          if work_left_to_do?
            client.puts @spec_files.shift
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
