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
