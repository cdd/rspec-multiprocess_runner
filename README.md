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

Use `multiprocess_rspec` to run a bunch of spec files:

    $ multiprocess_rspec 8 specs/*_spec.rb

The first argument is the number of processes to run. The remaining arguments
are names of spec files or directories containing spec files. To pass arguments
to the RSpec runner, use the `SPEC_OPTS` environment variable or the `.rspec`
file.

### Code

Create a coordinator and tell it to run:

    require 'rspec/multiprocess_runner/coordinator'

    process_count = 4
    rspec_args = %w(--backtrace)
    files = Dir['**/*_spec.rb']

    coordinator = RSpec::MultiprocessRunner::Coordinator(process_count, rspec_args, files)
    coordinator.run

## How it works



## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cdd/rspec-multiprocess_runner.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
