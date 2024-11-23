module Cymometer
  class RedisNotConfigured < StandardError; end

  class << self
    attr_writer :redis

    def redis
      raise RedisNotConfigured, "Please assign a Redis client to Cymometer.redis before using the gem." unless @redis

      @redis
    end
  end
end
