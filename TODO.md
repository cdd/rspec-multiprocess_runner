# Tests

Tricky things which I am manually testing:

* Timing out slow files (as_spec.rb)
* Recognizing and handling workers that die (ax_spec.rb, x*_spec.rb)
* Preserving the configuration from spec_helper, etc., across runs (w*_spec.rb)

Need to write automated tests for these (in addition to tests for all the basic
behavior). Maybe use Cucumber (like RSpec does for acceptance tests) to avoid
the weirdness of testing rspec within rspec.
