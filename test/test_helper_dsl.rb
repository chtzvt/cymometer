# frozen_string_literal: true

require "test_helper"
require_relative "support/dummy_helper_job"

class CymometerHelperDSLTest < Minitest::Test
  def test_stores_counters_in_class_config
    counters = CymometerHelperJob.cymometer_counters
    assert counters.key?(:fast_calls), "Should have :fast_calls key"
    assert counters.key?(:slow_calls), "Should have :slow_calls key"
  end

  def test_counter_returns_configured_cymometer_counter_instance
    job = CymometerHelperJob.new

    c = job.counter(:fast_calls)
    assert_instance_of Cymometer::Counter, c
    assert_equal "my_app:fast_calls", c.key
    assert_equal 10, c.limit
    assert_equal 30, c.window
    c.increment!

    c2 = job.counter(:slow_calls)
    assert_equal "my_app:some_static_string", c2.key
    assert_equal 3, c2.limit
    assert_equal 300, c2.window
    c2.increment!
  end
end
