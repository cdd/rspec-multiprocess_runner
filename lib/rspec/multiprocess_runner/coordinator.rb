# encoding: utf-8
require 'rspec/multiprocess_runner'
require 'rspec/multiprocess_runner/worker'
require 'rspec/multiprocess_runner/file_coordinator'

module RSpec::MultiprocessRunner
  class Coordinator
    def initialize(worker_count, files, options={})
      @worker_count = worker_count
      @file_timeout_seconds = options[:file_timeout_seconds]
      @example_timeout_seconds = options[:example_timeout_seconds]
      @test_env_number_first_is_1 = options[:test_env_number_first_is_1]
      @log_failing_files = options[:log_failing_files]
      @rspec_options = options[:rspec_options]
      @file_buffer = []
      @workers = []
      @stopped_workers = []
      @worker_results = []
      @file_coordinator = FileCoordinator.new(files, options)
    end

    def run
      @start_time = Time.now
      expected_worker_numbers.each do |n|
        create_and_start_worker_if_necessary(n)
      end
      (0..1).each do # rerun files missing from disconnects
        run_loop
        quit_all_workers
        @file_coordinator.finished
      end
      print_summary

      exit_code
    end

    def failed?
      0 < exit_code
    end

    def exit_code
      exit_code = 0
      exit_code |= 1 if any_example_failed?
      exit_code |= 2 if !failed_workers.empty?
      exit_code |= 4 if work_left_to_do? || @file_coordinator.missing_files.any?
      exit_code
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
      add_file_to_buffer
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
      @file_buffer.any?
    end

    def add_file_to_buffer
      file = @file_coordinator.get_file
      @file_buffer << file if file
    end

    def get_file
      if work_left_to_do?
        add_file_to_buffer
        @file_buffer.shift
      end
    end

    def failed_workers
      @file_coordinator.failed_workers
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
            ready_worker.run_file(get_file)
            send_results(ready_worker)
          end
        end
      end
    end

    def send_results(worker)
      results_to_send = worker.example_results - @worker_results
      @worker_results += results_to_send
      @file_coordinator.send_results(results_to_send)
    end

    def reap_one_worker(worker, reason)
      worker.reap
      worker.deactivation_reason = reason
      mark_worker_as_stopped(worker)
    end

    def mark_worker_as_stopped(worker)
      @stopped_workers << worker
      @workers.reject! { |w| w == worker }
      send_results(worker)
      @file_coordinator.send_worker_status(worker) if worker.deactivation_reason
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
          rspec_options: @rspec_options,
          test_env_number_first_is_1: @test_env_number_first_is_1
        )
        @workers << new_worker
        new_worker.start
        file = get_file
        new_worker.run_file(file)
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

      print_skipped_files_details
      print_pending_example_details(by_status_and_time["pending"])
      print_failed_example_details(by_status_and_time["failed"])
      print_missing_files
      log_failed_files(by_status_and_time["failed"].map(&:file_path).uniq  + @file_coordinator.missing_files) if @log_failing_files
      print_failed_process_details
      puts
      print_elapsed_time(elapsed)
      puts failed? ? "FAILURE" : "SUCCESS"
      print_example_counts(by_status_and_time)
    end

    def combine_example_results
      @file_coordinator.results.sort_by { |r| r.time_finished }
    end

    def any_example_failed?
      @file_coordinator.results.detect { |r| r.status == "failed" }
    end

    def print_skipped_files_details
      return if !work_left_to_do?
      puts
      puts "Skipped files:"
      @file_coordinator.remaining_files.each do |spec_file|
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

    def log_failed_files(failed_files)
      return if failed_files.nil?
      puts
      puts "Writing failures to file: #{@log_failing_files}"
      File.open(@log_failing_files, "w+") do |io|
        failed_files.each do |file|
          io << file
          io << "\n"
        end
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
      missing_count = @file_coordinator.missing_files.size
      process_failure_count = failed_workers.size
      skipped_count = @file_coordinator.remaining_files.size

      # Copied from RSpec
      summary = pluralize(example_count, "example")
      summary << ", " << pluralize(failure_count, "failure")
      summary << ", #{pending_count} pending" if pending_count > 0
      summary << ", " << pluralize(process_failure_count, "failed proc") if process_failure_count > 0
      summary << ", " << pluralize(skipped_count, "skipped file") if skipped_count > 0
      summary << ", " << pluralize(missing_count, "missing file") if missing_count > 0
      puts summary
    end

    def print_failed_process_details
      return if failed_workers.empty?
      puts
      puts "Failed processes:"
      failed_workers.each do |worker|
        puts "  - #{worker.slave}:#{worker.pid} (env #{worker.environment_number}) #{worker.deactivation_reason} on #{worker.current_file}"
      end
    end

    def print_missing_files
      return if @file_coordinator.missing_files.empty?
      puts
      puts "Missing files from disconnects:"
      @file_coordinator.missing_files.each { |file| puts "  + #{file} was given to a slave, which disconnected" }
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
