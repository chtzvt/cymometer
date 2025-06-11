# Helpers for configuring/working with Cymometer::Counters in classes
# (like background jobs) that require rate limit accounting
module Cymometer
  module Helper
    def self.included(base)
      base.extend ClassMethods
    end

    # ------------------------------------------------------
    # 1) Class-level methods
    # ------------------------------------------------------
    module ClassMethods
      #
      # DSL entrypoint
      #
      #   configure_cymometer do
      #     namespace "my_namespace"
      #     redis MyCustomRedis
      #
      #     counter :some_counter do
      #       limit 10
      #       window 60
      #       key { "dynamic_key_for_#{self.object_id}" }
      #     end
      #   end
      #
      def configure_cymometer(&block)
        DSL.new(self).instance_eval(&block)
      end

      #
      # Access the counters hash
      #
      def cymometer_counters
        @cymometer_counters ||= {}
      end

      #
      # Accessors for the optional shared namespace & redis client
      #
      def cymometer_namespace
        @cymometer_namespace
      end

      def cymometer_redis
        @cymometer_redis
      end

      #
      # Retrieve the stored counter config (hash) by name
      #
      def counter_config(name)
        cymometer_counters[name.to_sym]
      end
    end

    # ------------------------------------------------------
    # 2) Instance-level method to fetch a configured counter
    # ------------------------------------------------------
    #
    #   def perform
    #     c = counter(:some_counter)
    #     c.increment!
    #   end
    #
    def counter(name)
      config = self.class.counter_config(name)
      raise "No Cymometer counter named #{name.inspect} in #{self.class}" unless config

      # Memoize per-instance so we only build once
      @__cymometer_counter_cache ||= {}
      @__cymometer_counter_cache[name.to_sym] ||= build_cymometer_counter(config)
    end

    private

    def build_cymometer_counter(config)
      # Evaluate the 'key' if it's a Proc/Block
      real_key =
        if config[:key].respond_to?(:call)
          instance_exec(&config[:key]) # The block is run in instance context
        elsif config[:key]
          config[:key].to_s
        else
          config[:name].to_s # Fallback to the counter's name
        end

      Cymometer::Counter.new(
        key_namespace: config[:namespace] || self.class.cymometer_namespace || "cymometer",
        key: real_key,
        limit: config[:limit] || 1,
        window: config[:window] || 3600,
        redis: config[:redis] || self.class.cymometer_redis || Cymometer.redis
      )
    end

    # ------------------------------------------------------
    # 3) DSL builder classes for configure_cymometer
    # ------------------------------------------------------
    class DSL
      def initialize(klass)
        @klass = klass
      end

      def namespace(ns)
        @klass.instance_variable_set(:@cymometer_namespace, ns)
      end

      def redis(client)
        @klass.instance_variable_set(:@cymometer_redis, client)
      end

      def counter(name, &block)
        conf = CounterConfig.new(name)
        conf.instance_eval(&block) if block

        # Merge into class's counters
        new_counters = @klass.cymometer_counters.dup
        new_counters[name.to_sym] = conf.to_h
        @klass.instance_variable_set(:@cymometer_counters, new_counters)
      end
    end

    class CounterConfig
      attr_accessor :name, :limit, :window, :key, :redis, :namespace

      def initialize(name)
        @name = name.to_s
      end

      # standard:disable Lint/DuplicateMethods
      # standard:disable Style/TrivialAccessors

      # DSL methods
      def limit(val)
        @limit = val
      end

      def window(val)
        @window = val
      end

      def key(val = nil, &block)
        @key = block || val
      end

      def redis(client)
        @redis = client
      end

      def namespace(ns)
        @namespace = ns
      end

      # standard:enable Lint/DuplicateMethods
      # standard:enable Style/TrivialAccessors

      def to_h
        {
          name: @name,
          limit: @limit,
          window: @window,
          key: @key,
          redis: @redis,
          namespace: @namespace
        }
      end
    end
  end
end
