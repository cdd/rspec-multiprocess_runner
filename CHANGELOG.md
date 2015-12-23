# 0.2.0

* Add per-example timeout option. When using `multirspec` or the rake tasks, it
  defaults to 15 seconds (#2)
* **Breaking change**: per-file timeout is now disabled by default (#2)
* **Breaking change**: changed arguments for `Coordinator`'s constructor
* Correct signal used when requesting that stalled processes quit (use TERM
  instead of QUIT)

# 0.1.0

* Initial version
