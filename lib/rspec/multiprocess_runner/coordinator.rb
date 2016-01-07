# encoding: utf-8
require 'rspec/multiprocess_runner'
require 'rspec/multiprocess_runner/worker'

module RSpec::MultiprocessRunner
  class Coordinator
    def initialize(worker_count, files, options={})
      @worker_count = worker_count
      @file_timeout_seconds = options[:file_timeout_seconds]
      @example_timeout_seconds = options[:example_timeout_seconds]
      @log_failing_files = options[:log_failing_files]
      @rspec_options = options[:rspec_options]
      @spec_files = sort_files(files)
      @workers = []
      @stopped_workers = []
    end

    def run
      @start_time = Time.now
      expected_worker_numbers.each do |n|
        create_and_start_worker_if_necessary(n)
      end
      run_loop
      quit_all_workers
      print_summary

      !failed?
    end

    def failed?
      !failed_workers.empty? || !@spec_files.empty? || any_example_failed?
    end

    def shutdown(options={})
      if @shutting_down
        # Immediately kill the workers if shutdown is requested again
        end_workers_in_parallel(@workers.dup, :kill_now)
      else
        @shutting_down = true
        print "Shutting down #{pluralize(@workers.size, "worker")} …" if options[:print_summary]
        # end_workers_in_parallel modifies @workers, so dup before sending in
        end_workers_in_parallel(@workers.dup, :shutdown_now)
        if options[:print_summary]
          puts " done"
          print_summary
        end
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

    def worker_sockets
      @workers.map(&:socket)
    end

    def run_loop
      loop do
        act_on_available_worker_messages(0.3)
        reap_stalled_workers
        start_missing_workers
        quit_idle_unnecessary_workers
        break unless @workers.detect(&:working?)
      end
    end

    def quit_all_workers
      # quit_workers modifies @workers, so dup before sending in
      quit_workers(@workers.dup)
    end

    def end_workers_in_parallel(some_workers, end_method)
      end_threads = some_workers.map do |worker|
        # This method is not threadsafe because it updates instance variables.
        # But it's fine to run it outside of the thread because it doesn't
        # block.
        mark_worker_as_stopped(worker)
        Thread.new do
          worker.send(end_method)
        end
      end
      end_threads.each(&:join)
    end

    def quit_workers(some_workers)
      end_workers_in_parallel(some_workers, :quit_when_idle_and_wait_for_quit)
    end

    def work_left_to_do?
      !@spec_files.empty?
    end

    def failed_workers
      @stopped_workers.select { |w| w.deactivation_reason }
    end

    def act_on_available_worker_messages(timeout)
      while (select_result = IO.select(worker_sockets, nil, nil, timeout))
        select_result.first.each do |readable_socket|
          ready_worker = @workers.detect { |worker| worker.socket == readable_socket }
          next unless ready_worker # Worker is already gone
          worker_status = ready_worker.receive_and_act_on_message_from_worker
          if worker_status == :dead
            reap_one_worker(ready_worker, "died")
          elsif work_left_to_do? && !ready_worker.working?
            ready_worker.run_file(@spec_files.shift)
          end
        end
      end
    end

    def reap_one_worker(worker, reason)
      worker.reap
      worker.deactivation_reason = reason
      mark_worker_as_stopped(worker)
    end

    def mark_worker_as_stopped(worker)
      @stopped_workers << worker
      @workers.reject! { |w| w == worker }
    end

    def reap_stalled_workers
      @workers.select(&:stalled?).each do |stalled_worker|
        reap_one_worker(stalled_worker, "stalled")
      end
    end

    def expected_worker_numbers
      (1..@worker_count).to_a
    end

    def create_and_start_worker_if_necessary(n)
      if work_left_to_do?
        $stderr.puts "(Re)starting worker #{n}"
        new_worker = Worker.new(
          n,
          file_timeout_seconds: @file_timeout_seconds,
          example_timeout_seconds: @example_timeout_seconds,
          rspec_options: @rspec_options
        )
        @workers << new_worker
        new_worker.start
        new_worker.run_file(@spec_files.shift)
      end
    end

    def start_missing_workers
      if @workers.size < @worker_count && work_left_to_do?
        running_process_numbers = @workers.map(&:environment_number)
        missing_process_numbers = expected_worker_numbers - running_process_numbers
        missing_process_numbers.each do |n|
          create_and_start_worker_if_necessary(n)
        end
      end
    end

    def quit_idle_unnecessary_workers
      unless work_left_to_do?
        idle_workers = @workers.reject(&:working?)
        quit_workers(idle_workers)
      end
    end

    def print_summary
      elapsed = Time.now - @start_time
      by_status_and_time = combine_example_results.each_with_object({}) do |result, idx|
        (idx[result.status] ||= []) << result
      end
      count_examples(by_status_and_time)

      print_skipped_files_details
      print_pending_example_details(by_status_and_time["pending"])
      print_failed_example_details(by_status_and_time["failed"])
      log_failed_files(by_status_and_time["failed"]) if @log_failing_files
      print_failed_process_details
      puts
      print_elapsed_time(elapsed)
      puts failed? ? "FAILURE" : "SUCCESS"
      print_example_counts(by_status_and_time)
    end

    def combine_example_results
      (@workers + @stopped_workers).flat_map(&:example_results).sort_by { |r| r.time_finished }
    end

    def any_example_failed?
      (@workers + @stopped_workers).detect { |w| w.example_results.detect { |r| r.status == "failed" } }
    end

    def count_examples(example_results)
      @metadata = {}
      @metadata[:example_count] = example_results.map { |status, results| results.size }.inject(0) { |sum, ct| sum + ct }
      @metadata[:failure_count] = example_results["failed"] ? example_results["failed"].size : 0
      @metadata[:pending_count] = example_results["pending"] ? example_results["pending"].size : 0
    end

    def print_skipped_files_details
      return if @spec_files.empty?
      puts
      puts "Skipped files:"
      @spec_files.each do |spec_file|
        puts "  - #{spec_file}"
      end
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

    def log_failed_files(failed_example_results)
      return if failed_example_results.nil?
      return if failed_example_results.size > @metadata[:example_count] / 10.0

      failing_files = Hash.new { |h, k| h[k] = 0 }
      failed_example_results.each do |failure|
        failing_files[failure.file_path] += 1
      end

      puts
      puts "Writing failures to file: multiprocess.failures"
      File.open("multiprocess.failures", "w+") do |io|
        failing_files.each do |(k, _)|
          io << k
          io << "\n"
        end
      end
    end

    # Copied from RSpec
    def pluralize(count, string)
      "#{count} #{string}#{'s' unless count.to_f == 1}"
    end

    def print_example_counts(by_status_and_time)
      process_failure_count = failed_workers.size
      skipped_count = @spec_files.size

      # Copied from RSpec
      summary = pluralize(@metadata[:example_count], "example")
      summary << ", " << pluralize(@metadata[:failure_count], "failure")
      summary << ", #{@metadata[:pending_count]} pending" if @metadata[:pending_count] > 0
      summary << ", " << pluralize(process_failure_count, "failed proc") if process_failure_count > 0
      summary << ", " << pluralize(skipped_count, "skipped file") if skipped_count > 0
      puts summary
    end

    def print_failed_process_details
      return if failed_workers.empty?
      puts
      puts "Failed processes:"
      failed_workers.each do |worker|
        puts "  - #{worker.pid} (env #{worker.environment_number}) #{worker.deactivation_reason} on #{worker.current_file}"
      end
    end

    def print_elapsed_time(seconds_elapsed)
      minutes = seconds_elapsed.to_i / 60
      seconds = seconds_elapsed % 60
      m =
        if minutes > 0
          "%d minute%s" % [minutes, minutes == 1 ? '' : 's']
        end
      s =
        if seconds > 0
          "%.2f second%s" % [seconds, seconds == 1 ? '' : 's']
        end
      puts "Finished in #{[m, s].compact.join(", ")}"
    end
  end
end
