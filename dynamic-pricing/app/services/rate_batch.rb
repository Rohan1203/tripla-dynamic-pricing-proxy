class RateBatch
  def self.logger
    Rails.application.config.logger
  end

  def self.start
    self.logger.debug "Starting rate retrieval batch"
    loop do
      begin
        RateBatchService.call
      rescue StandardError => e
        self.logger.error "Error in rate retrieval batch: #{e.message}"
        # self.logger.error e.backtrace.join("\n")
      end
      interval = Rails.application.config.batch[:interval] || 5
      self.logger.debug "Sleeping for #{interval} minutes"
      sleep interval.minutes

    end
  end

  def self.start_async
    Thread.new do
      start
    end
  end
end
