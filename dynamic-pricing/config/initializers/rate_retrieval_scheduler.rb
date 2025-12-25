# Start the rate retrieval loop in a background thread when the server starts.
# We check if we are running in a server context to avoid starting it in console or rake tasks.

Rails.application.config.after_initialize do
  if defined?(Rails::Server) || defined?(Puma)
    Rails.logger.debug "Initializing rate retrieval background task"
    RateRetrievalLoop.start_async
  end
end

