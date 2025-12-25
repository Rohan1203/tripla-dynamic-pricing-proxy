class RateRetrievalLoop
  def self.start
    Rails.logger.debug "Starting rate retrieval batch"
    loop do
      begin
        RateRetrieverService.call
      rescue StandardError => e
        Rails.logger.error "Error in rate retrieval batch: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
      interval = (ConfigManager[:rate_retriever] || {})[:batch_interval] || 5
      Rails.logger.debug "Sleeping for #{interval} minutes"
      sleep interval.minutes

    end
  end

  def self.start_async
    Thread.new do
      start
    end
  end
end
