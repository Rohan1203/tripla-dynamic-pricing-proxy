# Instant batch call when upstream service comes alive and Redis is empty
Rails.application.config.after_initialize do
  if defined?(Rails::Server) || defined?(Puma)
    def upstream_alive?
      timeout = Rails.application.config.upstream_health_check[:timeout] rescue 5
      begin
        uri = URI(Rails.application.config.rate_api[:host])
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: timeout, read_timeout: timeout) do |http|
          response = http.head('/')
          response.is_a?(Net::HTTPSuccess)
        end
      rescue StandardError
        false
      end
    end

    Thread.new do
      Rails.logger.info("Starting instant batch call monitor")
      loop do
        if upstream_alive? && RedisService.get_all_rates.blank?
          Rails.logger.info("Upstream alive and Redis empty, calling batch instantly")
          begin
            PricingBatchService.call
          rescue StandardError => e
            Rails.logger.error("Instant batch call failed: #{e.message}")
          end
        end
        sleep 30 # check every 30 seconds
      end
    end
  end
end