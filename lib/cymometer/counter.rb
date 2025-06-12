require "securerandom"
require "digest/sha1"

module Cymometer
  class Counter
    class LimitExceeded < StandardError; end

    DEFAULT_WINDOW = 3600 # Default window is 1 hour

    attr_reader :window, :limit, :key

    INCREMENT_LUA_SCRIPT = <<-LUA.freeze
      local key = KEYS[1]
      local current_time = tonumber(ARGV[1])
      local window = tonumber(ARGV[2])
      local limit = tonumber(ARGV[3])

      -- Remove entries older than the window size
      redis.call('ZREMRANGEBYSCORE', key, 0, current_time - window)

      -- Get the current count
      local count = redis.call('ZCOUNT', key, current_time - window, '+inf')

      if count >= limit then
        -- Limit exceeded, do not increment
        return {0, count}
      else
        -- Increment the counter
        redis.call('ZADD', key, current_time, current_time)
        redis.call('EXPIRE', key, math.floor(window / 1000000))
        return {1, count + 1}
      end
    LUA

    DECREMENT_LUA_SCRIPT = <<-LUA.freeze
      local key = KEYS[1]
      local current_time = tonumber(ARGV[1])
      local window = tonumber(ARGV[2])

      -- Remove entries older than the window size
      redis.call('ZREMRANGEBYSCORE', key, 0, current_time - window)

      -- Attempt to remove the entry with the lowest score (oldest entry)
      local entries = redis.call('ZRANGEBYSCORE', key, current_time - window, '+inf', 'LIMIT', 0, 1)

      if next(entries) == nil then
        -- No entries to remove, safe no-op
        local count = 0
        return {1, count}
      else
        local member = entries[1]
        redis.call('ZREM', key, member)
        local count = redis.call('ZCOUNT', key, current_time - window, '+inf')
        return {1, count}
      end
    LUA

    @increment_sha = Digest::SHA1.hexdigest(INCREMENT_LUA_SCRIPT).freeze
    @decrement_sha = Digest::SHA1.hexdigest(DECREMENT_LUA_SCRIPT).freeze

    class << self
      attr_reader :increment_sha, :decrement_sha
    end

    def initialize(key_namespace: nil, key: nil, limit: nil, window: nil, redis: nil)
      @redis = redis || Cymometer.redis
      @key = "#{key_namespace || "cymometer"}:#{key || generate_key}"
      @window = window || DEFAULT_WINDOW
      @limit = limit || 1
    end

    # Atomically increments the counter and checks the limit
    def increment!
      current_time = (Time.now.to_f * 1_000_000).to_i # Microseconds
      window = @window * 1_000_000 # Convert to microseconds

      result = evalsha_with_fallback(
        :increment,
        keys: [@key],
        argv: [current_time, window, @limit]
      )

      success = result[0] == 1
      count = result[1].to_i

      raise LimitExceeded, "Limit of #{@limit} exceeded with count #{count}" unless success

      count
    end

    # Atomically decrements the counter by removing the oldest entry
    def decrement!
      current_time = (Time.now.to_f * 1_000_000).to_i
      window = @window * 1_000_000

      result = evalsha_with_fallback(
        :decrement,
        keys: [@key],
        argv: [current_time, window]
      )

      result[1].to_i
    end

    # Returns the current count
    def count
      current_time = (Time.now.to_f * 1_000_000).to_i
      window = @window * 1_000_000

      # Clean expired entries
      @redis.zremrangebyscore(@key, 0, current_time - window)
      @redis.zcount(@key, current_time - window, "+inf").to_i
    end

    # Executes a block if the counter can be incremented.
    # If the block raises an exception, decrements the counter and re-raises the exception.
    def transaction(rollback: true)
      increment!
      begin
        yield
      rescue => e
        decrement! if rollback
        raise e
      end
    end

    private

    def generate_key
      SecureRandom.uuid
    end

    def evalsha_with_fallback(type, keys:, argv:)
      script = (type == :increment) ? INCREMENT_LUA_SCRIPT : DECREMENT_LUA_SCRIPT
      sha = (type == :increment) ? self.class.increment_sha : self.class.decrement_sha

      @redis.evalsha(sha, keys: keys, argv: argv)
    rescue Redis::CommandError => e
      raise unless e.message.include?("NOSCRIPT")

      @redis.script(:load, script)
      @redis.evalsha(sha, keys: keys, argv: argv)
    end
  end
end
