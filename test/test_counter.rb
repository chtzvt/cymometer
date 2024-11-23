# frozen_string_literal: true

require "test_helper"

class TestCymometerCounter < Minitest::Test
  def setup
    super
    @counter = Cymometer::Counter.new(
      limit: 3,
      window: 1, # Use a short window (1 second) for testing
      redis: Cymometer.redis
    )
  end

  def test_increment_within_limit
    # Should be able to increment up to the limit
    assert_equal 1, @counter.increment!
    assert_equal 2, @counter.increment!
    assert_equal 3, @counter.increment!
  end

  def test_increment_beyond_limit
    # Exceeding the limit should raise LimitExceeded
    3.times { @counter.increment! }
    assert_raises Cymometer::Counter::LimitExceeded do
      @counter.increment!
    end
  end

  def test_decrement
    # Increment and then decrement
    @counter.increment!
    assert_equal 1, @counter.count

    @counter.decrement!
    assert_equal 0, @counter.count
  end

  def test_decrement_below_zero
    # Decrement when count is zero should be a no-op
    assert_equal 0, @counter.count
    @counter.decrement!
    assert_equal 0, @counter.count
  end

  def test_transaction_success
    # Transaction should execute the block if limit is not exceeded
    result = @counter.transaction do
      "success"
    end
    assert_equal "success", result
    assert_equal 1, @counter.count
  end

  def test_transaction_limit_exceeded
    # Transaction should not execute the block if limit is exceeded
    3.times { @counter.increment! }
    assert_raises Cymometer::Counter::LimitExceeded do
      @counter.transaction do
        flunk "This block should not be executed"
      end
    end
    assert_equal 3, @counter.count
  end

  def test_transaction_block_exception_with_rollback
    # If the block raises an exception and rollback is true (default), the counter should be decremented
    assert_raises RuntimeError do
      @counter.transaction do
        raise "Error in block"
      end
    end
    assert_equal 0, @counter.count
  end

  def test_transaction_block_exception_without_rollback
    # If the block raises an exception and rollback is false, the counter should remain incremented
    assert_raises RuntimeError do
      @counter.transaction(rollback: false) do
        raise "Error in block"
      end
    end
    assert_equal 1, @counter.count
  end

  def test_counter_respects_window
    # After the window expires, the counter should reset
    @counter.increment!
    sleep 1.1  # Wait for the window to expire

    assert_equal 0, @counter.count
    assert_equal 1, @counter.increment!
  end
end
