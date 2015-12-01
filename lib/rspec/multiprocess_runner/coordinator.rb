# encoding: utf-8
require 'rspec/multiprocess_runner'
require 'rspec/multiprocess_runner/worker'

module RSpec::MultiprocessRunner
  class Coordinator
    def initialize(process_count, file_timeout, rspec_options, files)
      @process_count = process_count
      @file_timeout = file_timeout
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
      print_summary

      !failed?
    end

    def failed?
      !@deactivated_workers.empty? || any_example_failed?
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
        new_worker = Worker.new(n, @file_timeout, @rspec_options)
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

    def print_summary
      by_status_and_time = combine_example_results.each_with_object({}) do |result, idx|
        (idx[result.status] ||= []) << result
      end
      print_pending_example_details(by_status_and_time["pending"])
      print_failed_example_details(by_status_and_time["failed"])
      print_failed_process_details
      puts
      puts failed? ? "FAILURE" : "SUCCESS"
      print_example_counts(by_status_and_time)
    end

    def combine_example_results
      (@workers + @deactivated_workers).flat_map(&:example_results).sort_by { |r| r.time_finished }
    end

    def any_example_failed?
      (@workers + @deactivated_workers).detect { |w| w.example_results.detect { |r| r.status == "failed" } }
    end

    def print_pending_example_details(pending_example_results)
      return if pending_example_results.nil?
      puts
      puts "Pending:"
      pending_example_results.each do |pending|
        puts
        puts pending.details.sub(/^\s*Pending:\s*/, '')
      end
    end

    def print_failed_example_details(failed_example_results)
      return if failed_example_results.nil?
      puts
      puts "Failures:"
      failed_example_results.each_with_index do |failure, i|
        puts
        puts "  #{i.next}) #{failure.description}"
        puts failure.details
      end
    end

    # Copied from RSpec
    def pluralize(count, string)
      "#{count} #{string}#{'s' unless count.to_f == 1}"
    end

    def print_example_counts(by_status_and_time)
      example_count = by_status_and_time.map { |status, results| results.size }.inject(0) { |sum, ct| sum + ct }
      failure_count = by_status_and_time["failed"] ? by_status_and_time["failed"].size : 0
      pending_count = by_status_and_time["pending"] ? by_status_and_time["pending"].size : 0
      process_failure_count = @deactivated_workers.size

      # Copied from RSpec
      summary = pluralize(example_count, "example")
      summary << ", " << pluralize(failure_count, "failure")
      summary << ", #{pending_count} pending" if pending_count > 0
      summary << ", " << pluralize(process_failure_count, "failed proc") if process_failure_count > 0
      puts summary
    end

    def print_failed_process_details
      return if @deactivated_workers.empty?
      puts
      puts "Failed processes:"
      @deactivated_workers.each do |worker|
        puts "  - #{worker.pid} (env #{worker.environment_number}) #{worker.deactivation_reason} on #{worker.current_file}"
      end
    end
  end
end
