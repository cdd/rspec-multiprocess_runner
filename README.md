# Rspec::MultiprocessRunner

This gem provides a mechanism for running a suite of RSpec tests in multiple
processes on the same machine and multiple machines (all reporting back to the
head node), potentially allowing substantial performance improvements.

It differs from `parallel_tests` in that it uses a coordinator process on each
machine to manage the workers, hand off work to them, and receive results. These
coordinators communicate via simple TCP messages with a head node coordinator to
remain in sync when running on multiple machines. This means it can dynamically
balance the workload among the processors and machines. It also means it can
provide consolidated results in one console.

It follows parallel_tests' environment variable conventions so it's easy to
use them together. (E.g., parallel_tests has a very nice set of rake tasks
for setting up parallel environments.)

## Benefits

* Running slow (IO-bound) specs in parallel can greatly reduce the wall-clock
  time needed to run a suite. Even CPU-bound specs can be aided
* Provides detailed logging of each example as it completes, including the
  failure message (you don't have to wait until the end to see the failure
  reason). This is only on the machine running the spec, a final print out does
  occur on the main machine upon completion, however.
* Detects, kills, and reports spec files that take longer than expected (five
  minutes by default).
* Detects and reports spec files that crash (without interrupting the
  remainder of the suite).
* Head node detects and reruns spec files that are not reported back by the
  nodes.

## Limitations

* Only works with RSpec 3 (>= 2.99). Does not work with previous versions of
  RSpec.
* Does not work on Windows or JRuby. Since it relies on `fork(2)`, it probably
  never will.
* Does not support RSpec custom formatters.
* The built-in output format is very verbose — it's intended for CI servers,
  where more logging is better.
* Intermediate-quality code. Happy path works, and workers are
  managed/restarted, but:
  * There's no test coverage of the runner itself, only auxiliaries.
* No security in the TCP messaging, but can work over SSH tunnels. Nodes do
  verify the file name given against the known files so it will not execute
  maliciously.

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

Runs as a head node node by default. The following command mimics the defaults:

    $ multirspec -p 2222 -n 5 [Files]

A corresponding node node, for a head node on `head_node.local` would be:

    $ multirspec -H head_node.local -p 2222 -s [Files]

N.B. You must include the same files for the nodes as the head node.

A corresponding set up for a node node using SSH would be:

    $ ssh -nNT -L 2500:localhost:2222 head_node.local &
    $ multirspec -H localhost -p 2500 -s [Files]
    $ kill $(jobs -p)

N.B. Ensure that the head node has tcp local port forwarding permitted.

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
    rspec_options = %w(--backtrace)
    files = Dir['**/*_spec.rb']

    coordinator = RSpec::MultiprocessRunner::Coordinator.new(
      worker_count, files,
      {
        file_timeout_seconds: per_file_timeout,
        rspec_options: rspec_options
      }
    )
    coordinator.run

… but you are probably better off using the command line interface.

## Runtime environment

### `TEST_ENV_NUMBER`

This runner provides each worker with a environment number so that you can
segment access to resources (databases, etc). For convenience, it follows the
same convention as `parallel_tests`.

* The environment number is provided as an environment variable named `TEST_ENV_NUMBER`
* The first environment number is `""` and subsequent ones are integers (`"2"`, `"3"`, etc.)

Like `parallel_tests` 2.3 and later, `multirspec` supports a `--first-is-1`
argument which makes the first environment number `"1"` instead. Use this to
have your multiprocess runs be isolated from the environment used in tests you
run normally, allowing you to to TDD while a long-running multiprocess run
continues in the background.

### Behavior options

All options are available via the `multirspec` command line interface. A couple
may alternatively be set in the calling environment.

* Worker count: instead of providing `-w 5`, set `PARALLEL_TEST_PROCESSORS="5"` or
  `MULTIRSPEC_WORKER_COUNT="5"` in the environment. If both `-w` and one of these
  vars is set, the value passed to `-w` will win.
* First-is-1: instead of providing `--first-is-1`, set
  `PARALLEL_TEST_FIRST_IS_1="true"` or `MULTIRSPEC_FIRST_IS_1="true"` in the
  environment.

These environment variables only apply to the CLI and rake task. If you
directly invoke `RSpec::MultiprocessRunner::Coordinator#run`, they are ignored.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cdd/rspec-multiprocess_runner.

### Project infrastructure

* [Source on GitHub](https://github.com/cdd/rspec-multiprocess_runner)
* [![Build Status](https://travis-ci.org/cdd/rspec-multiprocess_runner.svg?branch=master)](https://travis-ci.org/cdd/rspec-multiprocess_runner)
  [Continuous Integration on Travis-CI](https://travis-ci.org/cdd/rspec-multiprocess_runner)

### Release process

1. Verify that all desired changes have been merged & pushed to master.
2. Verify that the changelog is up to date (it should be kept up to date as
   changes are made, so this should just be a quick check).
3. Verify that the current master has passed on Travis.
4. Edit `version.rb` and remove `".pre"` from the version number. Save and commit.
5. Run `rake release`. This packages the gem and submits it to rubygems.org.
6. Edit `version.rb` and update to the next patch-level release, plus `.pre`.
   E.g. if you just released 0.6.10, update the version in `version.rb` to
   `"0.6.11.pre"`.
7. Add a heading for the new version number to `CHANGELOG.md`. E.g., if you
   just released 0.6.10, add "# 0.6.11" to the top of the changelog.
8. Save and commit the changes from steps 6 and 7.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
