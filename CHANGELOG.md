# 1.3.2

# 1.3.1

* Or use an environment variable for summary file.

# 1.3.0

* Add file output option

# 1.2.3

* Fix time library sporadic failure

# 1.2.2

* Fix typo in rake task

* Also adds specs that should have been included in last revision

# 1.2.1

* Fix missing files being triggered by empty files

* Fix missing files also being skipped files

* Add run identifier option to prevent incorrect spec version execution

# 1.2.0

* Can now run tests on multiple machines at a time by running in head node mode
  and others in node mode.  Nodes get which files to run when from the head node
  in a manner similar to how workers got files from the coordinator (which
  currently also still happens).

* Uses unencoded TCP, but works with SSH tunnels

* Adds associated command line and rake task options

* Reruns once locally if any files are missing from disconnects

# 1.1.0

* Redo exit codes for arguments, signal hanlding, and exceptions
* Update rake task to handle use given order flag

# 1.0.0

* Stop supporting Ruby < v2.0

# 0.5.2

* Added additional exit codes to multirspec runner. 0 for success, 1 for
  failures, 2 for some workers died, 4 for some files didn't get run.

# 0.5.1

* Added flag '--use-given-order' that respects the order files are passed on the
  commandline. The default is still to sort by file size.
* Removed some unneeded RSpec 2 configuration.

# 0.5.0

* Added support for RSpec 3. Did not maintain compatability with RSpec 2.

# 0.4.2

* Change to Rake.application.last_description as last_comment is deprecated

# 0.4.1

* Use RSpec::Core::Runner.disable_autorun! to avoid error messages when workers
  finish

# 0.4.0

* Change TEST_ENV_NUMBER values to match parallel_tests (#10)
* Allow for environment-variable-based defaults for worker count and first-is-1
  in `multirspec` (like #10, improving compatibility with parallel_tests)

# 0.3.0

* Require a filename for the `--log-failing-files` option (#9)
* Exit status for `multirspec` is only 0 on success and is always non-zero when
  there is any sort of failure (#8)

# 0.2.3

* Add `--log-failing-files` option (#7)

# 0.2.2

* Run specs in order of decreasing file size to increase worker utilization

# 0.2.1

* Include filename and line number in realtime output (#5)

# 0.2.0

* Terminate workers when the coordinator process is interrupted with SIGINT (^C)
  or SIGTERM (`kill` with no args) (#3)
* Add per-example timeout option. When using `multirspec` or the rake tasks, it
  defaults to 15 seconds (#2)
* **Breaking change**: per-file timeout is now disabled by default (#2)
* **Breaking change**: changed arguments for `Coordinator`'s constructor
* Correct signal used when requesting that stalled processes quit (use TERM
  instead of QUIT)
* Stop idle processes once there's no work, instead of waiting and stopping
  everything when the suite is complete

# 0.1.0

* Initial version
