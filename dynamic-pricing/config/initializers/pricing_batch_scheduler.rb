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

    # Use centralized RateHealthMonitor for instant recovery monitoring
    begin
      Helpers::RateHealthMonitor.start_async
    rescue StandardError => e
      logger.error "Failed to start RateHealthMonitor: #{e.class} - #{e.message}"
    end
  end
end
