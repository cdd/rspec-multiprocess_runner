require 'rspec/multiprocess_runner'
require 'rspec/multiprocess_runner/worker'

module RSpec::MultiprocessRunner
  class Coordinator
    def initialize(process_count, rspec_options, files)
      @process_count = process_count
      @rspec_options = rspec_options
      @spec_files = files
      @workers = []
      @deactivated_workers = []
    end

    def run
      expected_process_numbers.each do |n|
        create_and_start_worker_if_necessary(n)
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
        act_on_available_worker_messages(0.3)
        reap_stalled_workers
        start_missing_workers
        break unless @workers.detect(&:working?)
      end
    end

    def work_left_to_do?
      !@spec_files.empty?
    end

    def act_on_available_worker_messages(timeout)
      while (select_result = IO.select(worker_sockets, nil, nil, timeout))
        select_result.first.each do |readable_socket|
          ready_worker = @workers.detect { |worker| worker.socket == readable_socket }
          begin
            ready_worker.receive_and_act_on_message_from_worker
            if work_left_to_do? && !ready_worker.working?
              ready_worker.run_file(@spec_files.shift)
            end
          rescue Errno::ECONNRESET
            reap_one_worker(ready_worker, "died")
          end
        end
      end
    end

    def reap_one_worker(worker, reason)
      worker.reap
      @deactivated_workers << worker
      worker.deactivation_reason = reason
      @workers.reject! { |w| w == worker }
    end

    def reap_stalled_workers
      @workers.select(&:stalled?).each do |stalled_worker|
        reap_one_worker(stalled_worker, "stalled")
      end
    end

    def expected_process_numbers
      (1..@process_count).to_a
    end

    def create_and_start_worker_if_necessary(n)
      if work_left_to_do?
        $stderr.puts "(Re)starting worker #{n}"
        new_worker = Worker.new(n, @rspec_options)
        @workers << new_worker
        new_worker.start
        new_worker.run_file(@spec_files.shift)
      end
    end

    def start_missing_workers
      if @workers.size < @process_count && work_left_to_do?
        running_process_numbers = @workers.map(&:environment_number)
        missing_process_numbers = expected_process_numbers - running_process_numbers
        missing_process_numbers.each do |n|
          create_and_start_worker_if_necessary(n)
        end
      end
    end
  end
end
