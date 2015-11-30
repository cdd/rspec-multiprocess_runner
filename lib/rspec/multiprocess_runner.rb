require "rspec/multiprocess_runner/version"

module RSpec
  module MultiprocessRunner
    # An artifact of the datagram protocol — AFAICT, just needs to be the same
    # everywhere.
    PROTOCOL_VERSION = 0
    # Another element of the datagram protocol — needs to be longer than the
    # maximum size (in bytes) of any message.
    MESSAGE_MAX_LENGTH = 1000
  end
end
