# Start the rate retrieval loop in a background thread when the server starts.
# We check if we are running in a server context to avoid starting it in console or rake tasks.

Rails.application.config.after_initialize do
  if defined?(Rails::Server) || defined?(Puma)
    logger = Rails.application.config.logger
    logger.info "Initializing rate retrieval background task"

    # Main batch scheduler thread
    Thread.new do
      logger.info "Starting rate retrieval scheduler loop"

      loop do
        begin
          PricingBatchService.call
        rescue StandardError => e
          logger.error "Error in rate retrieval scheduler: #{e.class} - #{e.message}"
          logger.error e.backtrace.join("\n") if logger.respond_to?(:debug?) && logger.debug?
        end

        interval = Rails.application.config.batch[:interval] || 5
        logger.info "Sleeping for #{interval} minutes"
        sleep interval.minutes
      end
    end

    # Instant recovery monitor thread
    Thread.new do
      logger.info "Starting instant recovery monitor"

      def upstream_alive?
        timeout = Rails.application.config.upstream_health_check[:check_timeout_seconds] rescue 5
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

      loop do
        if upstream_alive? && RedisService.get_all_rates.blank?
          logger.info "Upstream recovered and Redis empty - triggering instant batch call"
          begin
            PricingBatchService.call
          rescue StandardError => e
            logger.error "Instant batch call failed: #{e.message}"
          end
        end
        sleep Rails.application.config.upstream_health_check[:check_interval_seconds] || 30 # Check every configured interval seconds
      end
    end
  end
end
