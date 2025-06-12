# Cymometer

<img src="./.github/cymometer.jpg" width="230" />

Cymometer is a decaying counter for rate limiting using Redis. It provides a simple and efficient mechanism for counting events over a sliding time window, which is useful in applications such as rate limiting.

Cymometer uses Redis sorted sets and Lua scripts to maintain atomic increment and decrement operations, ensuring accurate and thread-safe counting in distributed systems.

Cymometer is designed for simplicity and geared towards the distributed systems use case, such as applying rate-limiting to an application's business logic, background job processing, consumption of external APIs, and so on. Cymometer can also be used for request-based rate limiting, but gems like [rack-attack](https://github.com/rack/rack-attack) or Rails 8's [built-in rate limiting API](https://edgeguides.rubyonrails.org/security.html#brute-forcing-accounts) suit these applications well.

### Features

- **Atomic Operations:** Uses Redis Lua scripts for atomic increment and decrement.
- **Configurable Limits:** Set custom limits and time windows for your counters.
- **Transaction Support:** Execute blocks of code only if the counter can be incremented.
- **No Redis Client Dependency:** Works with any Redis client, as long as you assign it to `Cymometer.redis`.
- **Helper DSL:** Optional, makes it easy to add per-class, named rate limiters to jobs, service objects, or any Ruby class.

## Installation

```ruby
gem 'cymometer'
```

## Usage

### Configuration 

First, assign a Redis client to `Cymometer.redis` before using the gem:

```ruby
require 'redis'
require 'cymometer'

# Initialize Redis client
redis = Redis.new(host: 'localhost', port: 6379, db: 0)

# Assign Redis client to Cymometer
Cymometer.redis = redis
```

The Cymometer gem does not specify a dependency on a particular Redis client. You can configure a default Redis client to be used by all Cymometer counters, or supply one to the `Cymometer::Counter` initializer.

#### Global Configuration

```ruby
custom_redis = Redis.new(host: 'localhost', port: 6379, db: 1)
Cymometer.redis = custom_redis
```

#### Per-Counter Configuration

```ruby
custom_redis = Redis.new(host: 'localhost', port: 6379, db: 1)

counter = Cymometer::Counter.new(
  key_namespace: 'api',
  key: 'user_456',
  limit: 500,
  window: 1800,     # 30 minutes
  redis: custom_redis
)
```

### Create a Counter 

Create a new counter with a namespace, key, limit, and window size:

```ruby
counter = Cymometer::Counter.new(
  key_namespace: 'api',
  key: 'user_123',
  limit: 1000, # Maximum allowed actions in the time window
  window: 3600 # Time window in seconds (e.g., 1 hour)
)
```

#### Options 

- `key_namespace`: A namespace to group related counters.
- `key`: A unique identifier for the counter (e.g., user ID).
- `limit`: The maximum number of allowed actions within the time window.
- `window`: The time window in seconds over which the actions are counted.


### Increment a Counter 

To increment the counter and check if the limit has been exceeded:

```ruby
begin
  count = counter.increment!
  puts "Counter incremented. Current count: #{count}"
rescue Cymometer::Counter::LimitExceeded => e
  puts "Rate limit exceeded: #{e.message}"
end
```

If the limit is not exceeded, increment! returns the current count. Otherwise, a `Cymometer::Counter::LimitExceeded` exception is raised.

### Decrement a Counter 

If you need to undo an action (e.g., due to an error), you can decrement the counter:

```ruby
count = counter.decrement!
puts "Counter decremented. Current count: #{count}"
```

The `decrement!` method safely decrements the counter by removing the oldest entry. If the counter is already at zero, it remains unchanged.

### Getting the Current Count

To retrieve the current count without modifying the counter:

```ruby
puts "Current count: #{counter.count}"
```

### Using Transactions

Transactions allow you to execute a block of code only if the counter can be incremented:

```ruby
begin
  result = counter.transaction do
    # Your rate-limited code goes here
    perform_api_call
    "Success"
  end
  puts result
rescue Cymometer::Counter::LimitExceeded => e
  puts "Rate limit exceeded: #{e.message}"
rescue => e
  puts "An error occurred: #{e.message}"
end
```

If the counter can be incremented, the block is executed. If the block raises an exception, the counter is decremented automatically, and the exception is re-raised. If the limit is exceeded, the block is not executed, and `Cymometer::Counter::LimitExceeded` is raised.

#### Rollback Behavior

If you want the counter to remain incremented even when an exception occurs (i.e., not roll back the increment), set `rollback` to false:

```ruby
begin
  result = counter.transaction(rollback: false) do
    # Your rate-limited code here
    perform_api_call
    "Success"
  end
  puts result
rescue Cymometer::Counter::LimitExceeded => e
  puts "Rate limit exceeded: #{e.message}"
rescue => e
  puts "An error occurred: #{e.message}"
  # The counter remains incremented despite the exception
end
```

###### Rollback Enabled (default)

Useful when you want to ensure that only successful actions count against the rate limit (e.g., API endpoints where you don’t want failed requests (due to server errors) to penalize the user).

###### Rollback Disabled (with `rollback: false`)

Useful when you want all attempts, successful or not, to count against the rate limit to prevent abuse (e.g., login attempts where you need to prevent brute-force attacks by limiting the number of attempts regardless of success).

### Cymometer::Helper DSL

The `Cymometer::Helper` DSL makes it easy to add per-class, named rate limiters to jobs, service objects, or any Ruby class. Counters are lazily instantiated and memoized per instance, so repeat calls are efficient. You declare your counters and options up front with a simple block, then access them with the counter method. No boilerplate required!

#### When to Use
- **Background jobs:** Limit how often certain work can be performed per job type or account.
- **Custom service classes:** Rate limit expensive or risky operations across different classes or namespaces.
- **Dynamic keys:** Build counter keys from instance data (e.g., a user ID, IP address, etc) at runtime.

#### How It Works
1. Include the module in your class.
2. Declare counters and options in a configure_cymometer block using a simple DSL.
3. Access counters by name with counter(:counter_name) anywhere in your class.

#### DSL Options
- `namespace "my_app"`: Sets a prefix for all counter keys.
- `counter :name do ... end`: Defines a new counter. Inside the block, you can specify:
  - `limit`: Max actions per window.
  - `window`: Time window in seconds.
  - `key { ... }`: (Optional) Block to dynamically build the counter's unique key using instance data.


Here's an example:

```ruby
class MyJob
  include Cymometer::Helper

  configure_cymometer do
    namespace "my_app"

    counter :fast_calls do
      limit 10        # max 10 per window
      window 30       # 30 seconds
    end

    counter :slow_calls do
      limit 3
      window 300      # 5 minutes
      key { some_dynamic_method } # key is built at runtime
    end
  end

  def perform
    # Increment and check the :fast_calls rate limit
    counter(:fast_calls).increment!

    # Use a transaction for the :slow_calls counter
    counter(:slow_calls).transaction do
      do_something_slow
    end
  end

  private

  def some_dynamic_method
    "user_#{user_id}"
  end
end
```

> [!NOTE]
> Centralizing your rate limits into configuration (e.g, `Rails.application.config_for(:rate_limits)[:my_job][:fast_calls]` in Rails) is a great way to keep them clear, maintainable, and easy to test.

#### Testing with Cymometer::Helper

<details>

<summary> 🛠️ Tips and Tricks </summary>


`Cymometer::Helper` makes it very straightforward to test rate limiting configuration and behavior in your test suite. We'll use RSpec for these examples, but you could achieve the same result with Minitest or your preferred test suite.

To start, create a `Cymometer::Counter` test double:

```ruby
let(:test_counter) { instance_double("Cymometer::Counter") }
```

Then, add some stubs. In the example below, we configure spy methods to return our test double from `Cymometer::Counter#new`, and configure the `transaction` and `increment!` methods to increment an instance variable counter for our tests. 

```ruby
  allow(Cymometer::Counter).to receive(:new).and_return(test_counter)
  @transactions_counter = 0

  allow(test_counter).to receive(:transaction) do |&block|
    @transactions_counter += 1
    block&.call
  end

  allow(test_counter).to receive(:increment!) { @transactions_counter += 1 }
```

You can then wire up tests for rate limiting behavior. Here's an example:


```ruby
  describe "rate limiting behavior" do
    before do
      @transactions_counter = 0
    end

    # Tests for configuration
    it "configures and uses Cymometer counters for rate limiting" do
      counters = described_class.cymometer_counters

      expect(counters[:hour_api_calls]).not_to be_nil
      expect(counters[:hour_api_calls][:limit]).to equal(Rails.application.config_for(:rate_limits)[:api_calls_job][:per_hour])
      expect(counters[:hour_api_calls][:window]).to equal(1.hour.to_i)
    end

    # Tests for behavior
    context "for a project in trial mode" do
      let(:job) { described_class.new }

      before do
        allow(project).to receive(:trial_mode?).and_return(true)
      end

      it "increments all counters" do
        @transactions_counter = 0

        described_class.perform_now(backlog_entry)

        expect(@transactions_counter).to eq(2)
      end
    end
  end

```

</details>

### Patterns

#### Retry with ActiveJob 

If you're using Cymometer to rate limit background jobs (perhaps ones that consume an external API), you can use ActiveJob's `retry_on` mechanism to re-enqueue the job automatically if a rate limit exception is raised:

```ruby
retry_on Cymometer::Counter::LimitExceeded, wait: :polynomially_longer, attempts: :unlimited, jitter: 0.5
```

Depending on your setup, you might also combine Cymometer with [concurrency limiting](https://github.com/rails/solid_queue/?tab=readme-ov-file#concurrency-controls) and [job uniqueness](https://github.com/veeqo/activejob-uniqueness) mechanisms for finer-grained control.


#### Interlocking Rate Limits

Sometimes, you might be working with an external API or system that imposes multi-level rate limits, e.g.:

- No more than X requests _per hour_, **and** no more than Y requests _per minute_.

Thankfully, this is easy to address with Cymometer: Just nest transactions and increment operations against multiple counters alongside or within one another. 

You have a few options to consider depending on rollback behavior, exception handling, and so on.

```ruby
counter(:per_hour).increment!
counter(:per_minute).increment!

# Or: 

counter(:per_hour).transaction do
  counter(:per_minute).increment!
end

# Or: 

counter(:per_hour).transaction do
  counter(:per_minute).transaction do 
    # Do your thing...
  end 
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/chtzvt/cymometer.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
