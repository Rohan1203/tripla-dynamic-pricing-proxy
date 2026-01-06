require 'redis'
require 'connection_pool'
require 'json'

class RedisService
  class RedisError < StandardError; end
  class ConnectionError < RedisError; end
  class TimeoutError < RedisError; end

  class << self
    attr_reader :config

    # Initialize the Redis connection pool
    def initialize_pool(config)
      @config = config
      pool_size = config[:pool_size] || 5
      pool_timeout = config[:pool_timeout] || 5

      @pool = ConnectionPool.new(size: pool_size, timeout: pool_timeout) do
        Redis.new(
          host: config[:host],
          port: config[:port],
          password: config[:password],
          db: config[:db] || 0,
          timeout: config[:timeout] || 5,
          reconnect_attempts: config[:reconnect_attempts] || 3
        )
      end

      Rails.logger.info("Redis connection pool initialized with #{pool_size} connections")
    rescue StandardError => e
      Rails.logger.error("Failed to initialize Redis pool: #{e.message}")
      raise ConnectionError, "Failed to initialize Redis connection pool: #{e.message}"
    end

    # Get the connection pool, lazily initializing it if needed.
    # This makes the system more robust when the Redis initializer failed once
    # (e.g. Redis was down at boot) or when running in non-server contexts.
    def pool
      return @pool if @pool

      Rails.logger.warn("[pricing] Redis pool not initialized; attempting lazy initialization")
      begin
        config = @config || load_config_from_file
        initialize_pool(config)
        @pool
      rescue StandardError => e
        Rails.logger.error("[pricing] Lazy Redis pool initialization failed: #{e.class} - #{e.message}")
        raise ConnectionError, "Redis pool not initialized and lazy initialization failed: #{e.message}"
      end
    end

    # Ping Redis to check connection
    def ping
      with_redis { |redis| redis.ping == 'PONG' }
    rescue StandardError => e
      Rails.logger.error("Redis ping failed: #{e.message}")
      false
    end

    # Store rates data with automatic expiry
    def store_rates(rates_data, ttl: nil)
      ttl ||= Rails.application.config.redis_ttl[:rate]
      return false if rates_data.nil? || rates_data.empty?

      with_redis do |redis|
        redis.pipelined do |pipeline|
          # Store each rate individually with a composite key
          rates_data.each do |rate|
            key = rate_key(rate['period'], rate['hotel'], rate['room'])
            pipeline.setex(key, ttl, rate.to_json)
          end

          # Store all rates as a set for batch retrieval
          pipeline.setex('rates:all', ttl, rates_data.to_json)
          
          # Store last update timestamp
          pipeline.set('rates:last_updated', Time.current.to_i)
        end

        Rails.logger.info("Stored #{rates_data.size} rates in Redis with TTL of #{ttl} seconds")
        true
      end
    rescue StandardError => e
      Rails.logger.error("Failed to store rates in Redis: #{e.message}")
      false
    end

    # Retrieve a specific rate
    def get_rate(period:, hotel:, room:)
      key = rate_key(period, hotel, room)
      
      with_redis do |redis|
        data = redis.get(key)
        return nil unless data

        rate = JSON.parse(data)
        Rails.logger.debug("Retrieved rate from Redis: #{key}")
        rate
      end
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse rate from Redis: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("Failed to retrieve rate from Redis: #{e.message}")
      nil
    end


    # Check if rates are still fresh (within TTL)
    def rates_fresh?
      with_redis do |redis|
        last_updated = redis.get('rates:last_updated')
        return false unless last_updated

        updated_at = Time.at(last_updated.to_i)
        age_in_seconds = Time.current.to_i - updated_at.to_i
        rate_ttl = Rails.application.config.redis_ttl[:rate]
        
        fresh = age_in_seconds < rate_ttl
        Rails.logger.debug("Rates age: #{age_in_seconds}s, fresh: #{fresh}")
        fresh
      end
    rescue StandardError => e
      Rails.logger.error("Failed to check rate freshness: #{e.message}")
      false
    end


    # Generic key-value retrieval
    def get(key)
      with_redis do |redis|
        value = redis.get(key)
        deserialize_value(value)
      end
    rescue StandardError => e
      Rails.logger.error("Failed to get key '#{key}' from Redis: #{e.message}")
      nil
    end

    private

    # Execute Redis commands with connection from pool
    def with_redis(&block)
      pool.with do |redis|
        block.call(redis)
      end
    rescue ConnectionPool::TimeoutError => e
      Rails.logger.error("Redis connection pool timeout: #{e.message}")
      raise TimeoutError, "Redis connection pool timeout"
    rescue Redis::BaseConnectionError => e
      Rails.logger.error("Redis connection error: #{e.message}")
      raise ConnectionError, "Redis connection error: #{e.message}"
    rescue StandardError => e
      Rails.logger.error("Redis operation error: #{e.class} - #{e.message}")
      raise RedisError, "Redis operation failed: #{e.message}"
    end

    # Load Redis configuration from config/redis.yml for the current Rails.env
    # Used for lazy pool initialization when @config is not set.
    def load_config_from_file
      require 'yaml'
      require 'erb'

      path = Rails.root.join('config', 'redis.yml')
      unless File.exist?(path)
        raise ConnectionError, "Redis configuration file not found at #{path}"
      end

      raw       = YAML.load(ERB.new(File.read(path)).result)
      env_conf  = raw[Rails.env] || {}
      env_conf.transform_keys!(&:to_sym)
      env_conf
    rescue StandardError => e
      Rails.logger.error("[pricing] Failed to load Redis config from file: #{e.class} - #{e.message}")
      raise ConnectionError, "Failed to load Redis configuration: #{e.message}"
    end

    # Generate a composite key for rate storage
    def rate_key(period, hotel, room)
      "rate:#{period}:#{hotel}:#{room}"
    end

    # Serialize values for storage
    # (kept for future use if set() is reintroduced)
    def serialize_value(value)
      case value
      when String
        value
      when Integer, Float, TrueClass, FalseClass
        value.to_s
      else
        value.to_json
      end
    end

    # Deserialize values from storage
    def deserialize_value(value)
      return nil if value.nil?
      return value if value.is_a?(String) && !json_string?(value)
      
      JSON.parse(value)
    rescue JSON::ParserError
      value
    end

    # Check if string is JSON
    def json_string?(str)
      str.start_with?('{', '[')
    end
  end
end
