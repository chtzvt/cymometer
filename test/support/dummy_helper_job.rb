class CymometerHelperJob
  include Cymometer::Helper

  configure_cymometer do
    namespace "my_app"

    counter :fast_calls do
      limit 10
      window 30
    end

    counter :slow_calls do
      limit 3
      window 300
      key { method_for_counter_key }
    end
  end

  def perform
    fast_counter = counter(:fast_calls)
    slow_counter = counter(:slow_calls)

    fast_counter.increment!
    puts "fast_counter count=#{fast_counter.count}"

    slow_counter.transaction do
      do_something_slow
    end
  rescue Cymometer::Counter::LimitExceeded => e
    puts "Rate limit exceeded: #{e.message}"
  end

  def do_something_slow
    nil
  end

  private

  def method_for_counter_key
    :some_static_string
  end
end
