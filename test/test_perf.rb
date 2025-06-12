# frozen_string_literal: true

require "test_helper"
require "benchmark"

class TestCymometerCounterPerformance < Minitest::Test
  def setup
    super
    @counter_key = SecureRandom.uuid
    @counter = Cymometer::Counter.new(
      key: @counter_key,
      limit: 1000,
      window: 60,
      redis: Cymometer.redis
    )
  end

  def test_high_throughput_increment
    iterations = 1000
    elapsed_time = Benchmark.realtime do
      iterations.times { @counter.increment! }
    end

    puts "Increment throughput: #{iterations / elapsed_time} increments/sec"

    assert_equal iterations, @counter.count
  end

  def test_concurrent_increment_stress
    threads = []
    thread_count = 10
    increments_per_thread = 100
    test_counter_key = SecureRandom.uuid

    test_counter = Cymometer::Counter.new(
      key: test_counter_key,
      limit: thread_count * increments_per_thread,
      window: 60,
      redis: Redis.new(**REDIS_CLIENT_OPTS)
    )

    elapsed_time = Benchmark.realtime do
      thread_count.times do
        threads << Thread.new do
          # Create a separate Redis client per thread
          redis_client = Redis.new(**REDIS_CLIENT_OPTS)
          local_counter = Cymometer::Counter.new(
            key: test_counter_key,
            limit: thread_count * increments_per_thread,
            window: 60,
            redis: redis_client
          )

          increments_per_thread.times do
            local_counter.increment!
          rescue Cymometer::Counter::LimitExceeded
            # Ignore limit exceeded errors for this stress test
          end

          redis_client.close
        end
      end
      threads.each(&:join)
    end

    total_attempts = thread_count * increments_per_thread
    final_count = test_counter.count

    puts "Concurrent increments: #{final_count}/#{total_attempts} completed in #{elapsed_time.round(2)} seconds"

    assert final_count <= test_counter.limit
  end

  def test_high_volume_transactions
    transaction_count = 500

    elapsed_time = Benchmark.realtime do
      transaction_count.times do
        @counter.transaction do
          true
        end
      end
    end

    puts "Transaction throughput: #{transaction_count / elapsed_time} transactions/sec"

    assert_equal transaction_count, @counter.count
  end

  def teardown
    # Clear counter after tests
    Cymometer.redis.del(@counter.key)
    super
  end
end
