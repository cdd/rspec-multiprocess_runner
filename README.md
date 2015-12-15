# Rspec::MultiprocessRunner

This gem provides a mechanism for running a suite of RSpec tests in multiple
processes on the same machine, potentially allowing substantial performance
improvements.

It differs from `parallel-tests` in that it uses a coordinator process to manage
the workers, hand off work to them, and receive results. This means it can
dynamically balance the workload among the processors. It also means it can
provide consolidated results in the console.

It does follow parallel-tests' `TEST_ENV_NUMBER` convention so it's easy to
switch.

## Benefits

* Running slow (IO-bound) specs in parallel can greatly reduce the wall-clock
  time needed to run a suite. Even CPU-bound specs can be aided
* Provides detailed logging of each example as it completes, including the
  failure message (you don't have to wait until the end to see the failure
  reason).
* Detects, kills, and reports spec files that take longer than expected (five
  minutes by default).
* Detects and reports spec files that crash (without interrupting the
  remainder of the suite).

## Limitations

* Only works with RSpec 2. Does not work with RSpec 3.
* Does not work on Windows or JRuby. Since it relies on `fork(2)`, it probably
  never will.
* Does not support RSpec custom formatters.
* The built-in output format is very verbose — it's intended for CI servers,
  where more logging is better.
* Intermediate-quality code. Happy path works, and workers are
  managed/restarted, but:
  * There's no test coverage of the runner itself, only auxiliaries.
  * Does not handle the coordinator process dying (e.g., from `^C`).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rspec-multiprocess_runner'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rspec-multiprocess_runner

## Usage

### Command line

Use `multirspec` to run a bunch of spec files:

    $ multirspec spec

Runs three workers by default — use `-w` to chose another count. `--help` will
detail the other options.

You can provide options that will be passed to the separate RSpec processes by
including them after a `--`:

    $ multirspec -w 5 spec -- -b -I ./lib

In this case, each RSpec process would receive the options `-b -I ./lib`. Note
that not that many RSpec options really make sense to pass this way. In
particular, file selection and output formatting options are unlikely to work
the way you expect.

### Rake

There is a rake task wrapper for `multirspec`:

    require 'rspec/multiprocess_runner/rake_task'

    RSpec::MultiprocessRunner::RakeTask.new(:spec) do |t|
      t.worker_count = 5
      t.pattern = "spec/**/*_spec.rb"
    end

See its source for the full list of options.

### Code

Create a coordinator and tell it to run:

    require 'rspec/multiprocess_runner/coordinator'

    worker_count = 4
    per_file_timeout = 5 * 60    # 5 minutes in seconds
    rspec_args = %w(--backtrace)
    files = Dir['**/*_spec.rb']

    coordinator = RSpec::MultiprocessRunner::Coordinator(worker_count, per_file_timeout, rspec_args, files)
    coordinator.run

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cdd/rspec-multiprocess_runner.

### Project infrastructure

* [Source on GitHub](https://github.com/cdd/rspec-multiprocess_runner)
* [![Build Status](https://travis-ci.org/cdd/rspec-multiprocess_runner.svg?branch=master)](https://travis-ci.org/cdd/rspec-multiprocess_runner)
  [Continuous Integration on Travis-CI](https://travis-ci.org/cdd/rspec-multiprocess_runner)

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
