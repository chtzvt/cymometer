# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "cymometer"

require "minitest/autorun"
require "redis"

CYMOMETER_TEST_REDIS_DB = 15
CYMOMETER_TEST_REDIS_URL = "redis://localhost:6379"

REDIS_CLIENT_OPTS = {
  url: ENV["REDIS_URL"] || CYMOMETER_TEST_REDIS_URL,
  db: ENV["REDIS_DB"] || CYMOMETER_TEST_REDIS_DB
}

Cymometer.redis = Redis.new(**REDIS_CLIENT_OPTS)

module Minitest
  class Test
    def setup
      Cymometer.redis.flushdb
    end
  end
end
