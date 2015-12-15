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

## Limitations

* Only tested with RSpec 2. Probably does not work with RSpec 3, so it is
  excluded in the gemspec.
* Spike-quality code. If this actually works I'll make it better.

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

Runs three processes by default — use `-c` to chose another count. `--help` will
detail the other options.

You can provide options that will be passed to the separate RSpec processes by
including them after a `--`:

    $ multirspec -c 5 spec -- -b -I ./lib

In this case, each RSpec process would receive the options `-b -I ./lib`. Note
that not that many RSpec options really make sense to pass this way. In
particular, file selection and output formatting options are unlikely to work
the way you expect.

### Code

Create a coordinator and tell it to run:

    require 'rspec/multiprocess_runner/coordinator'

    process_count = 4
    per_file_timeout = 5 * 60    # 5 minutes in seconds
    rspec_args = %w(--backtrace)
    files = Dir['**/*_spec.rb']

    coordinator = RSpec::MultiprocessRunner::Coordinator(process_count, per_file_timeout, rspec_args, files)
    coordinator.run

## How it works



## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cdd/rspec-multiprocess_runner.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
