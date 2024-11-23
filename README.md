# Cymometer

<img src="./.github/cymometer.jpg" width="230" />

Cymometer is a decaying counter for rate limiting using Redis. It provides a simple and efficient mechanism for counting events over a sliding time window, which is useful in applications such as rate limiting.

Cymometer uses Redis sorted sets and Lua scripts to maintain atomic increment and decrement operations, ensuring accurate and thread-safe counting in distributed systems.

### Features

- **Atomic Operations:** Uses Redis Lua scripts for atomic increment and decrement.
- **Configurable Limits:** Set custom limits and time windows for your counters.
- **Transaction Support:** Execute blocks of code only if the counter can be incremented.
- **No Redis Client Dependency:** Works with any Redis client, as long as you assign it to `Cymometer.redis`.

## Installation

```ruby
packfiles_internal do
  gem 'cymometer'
end 
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

##### Use Cases 

###### Rollback Enabled (default)

Useful when you want to ensure that only successful actions count against the rate limit (e.g., API endpoints where you don’t want failed requests (due to server errors) to penalize the user).

###### Rollback Disabled (with `rollback: false`)

Useful when you want all attempts, successful or not, to count against the rate limit to prevent abuse (e.g., login attempts where you need to prevent brute-force attacks by limiting the number of attempts regardless of success).


### Getting the Current Count

To retrieve the current count without modifying the counter:

```ruby
puts "Current count: #{counter.count}"
```

### Configuring Redis

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/packfiles/cymometer.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
