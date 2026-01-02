# Initialize Redis connection pool at application startup
require 'yaml'
require 'erb'

Rails.application.config.after_initialize do
  begin
    # Load Redis configuration
    redis_config_path = Rails.root.join('config', 'redis.yml')
    
    if File.exist?(redis_config_path)
      raw_config = YAML.load(ERB.new(File.read(redis_config_path)).result)
      env_config = raw_config[Rails.env] || {}
      
      # Convert string keys to symbols
      redis_config = env_config.transform_keys(&:to_sym)
      
      # Initialize the Redis connection pool
      RedisService.initialize_pool(redis_config)
      
      # Test the connection
      if RedisService.ping
        Rails.logger.info("Redis connection established successfully")
      else
        Rails.logger.warn("Redis ping failed - connection may not be working properly")
      end
    else
      Rails.logger.error("Redis configuration file not found at #{redis_config_path}")
    end
  rescue StandardError => e
    Rails.logger.error("Failed to initialize Redis: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
  end
end
