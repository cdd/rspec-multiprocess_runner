require 'rspec/multiprocess_runner'
require 'rspec/multiprocess_runner/worker'

module RSpec::MultiprocessRunner
  class Coordinator
    def initialize(process_count, rspec_options, files)
      @process_count = process_count
      @rspec_options = rspec_options
      @spec_files = files
      @workers = (1..process_count).map { |env_number| Worker.new(env_number, rspec_options) }
    end

    def run
      @workers.each do |worker|
        unless @spec_files.empty?
          worker.start
          # TODO track files non-destructively, timeout, etc.
          worker.run_file(@spec_files.shift)
        end
      end
      run_loop
      @workers.each do |worker|
        worker.quit
        worker.wait_until_quit
      end
    end

    private

    def worker_sockets
      @workers.map(&:socket)
    end

    def run_loop
      loop do
        select_result = IO.select(worker_sockets, nil, nil, 5)
        if select_result
          first_readable = select_result.first.first
          ready_worker = @workers.detect { |worker| worker.socket == first_readable }
          ready_worker.receive_and_act_on_message_from_worker
          if !@spec_files.empty? && !ready_worker.working?
            ready_worker.run_file(@spec_files.shift)
          end
        end
        break unless @workers.detect(&:working?)
        # TODO: reap stalled workers, etc.
      end
    end
  end
end
