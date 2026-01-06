require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Ensure Redis password for local development (used by config/redis.yml)
  ENV['REDIS_PASSWORD'] ||= '04aa6f42aa03f220c2ae9a276cd68c62'
  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded any time
  # it changes. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.enable_reloading = true

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing
  config.server_timing = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join("tmp/caching-dev.txt").exist?
    config.cache_store = :memory_store
    config.public_file_server.headers = {
      "Cache-Control" => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Highlight code that enqueued background job in logs.
  config.active_job.verbose_enqueue_logs = true


  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Uncomment if you wish to allow Action Cable access from any origin.
  # config.action_cable.disable_request_forgery_protection = true

  # Raise error when a before_action's only/except options reference missing actions
  config.action_controller.raise_on_missing_callback_actions = true

  # Optional: reduce dev log volume in console
  # 
  config.log_level = :info
  config.active_record.logger = nil

  log_file = File.open(Rails.root.join("log/application_#{Rails.env}.log"), "a")
  log_file.sync = true
  config.logger = ActiveSupport::Logger.new(log_file)
  config.logger.formatter = proc do |severity, datetime, progname, msg|
    caller_info = caller.find { |c| c.include?('/app/') }
    file = caller_info ? File.basename(caller_info.split(':').first) : nil
    line = caller_info ? caller_info[/:\d+:/][1..-2] : nil
    {
      time: datetime.to_s,
      level: severity,
      logger_name: Rails.env,
      file: file,
      line: line,
      thread_id: Thread.current.object_id,
      message: msg
    }.to_json + "\n"
  end

  # Rate retriever configuration
  config.rate_api = { host: "http://localhost:8080/pricing", token: "04aa6f42aa03f220c2ae9a276cd68c62" }
  config.retry = { count: 3, base_backoff_seconds: 1, backoff_multiplier: 2, max_backoff_seconds: 30 }
  config.batch = { interval: 5, failure_interval: 1 } #minute

  # Pricing behaviour tuning
  config.pricing = {
    db_max_age_seconds:      30, # how long historical DB data is considered fresh
    refresh_window_seconds:   5  # coalescing window for upstream refreshes
  }

  config.upstream_health_check = { check_timeout_seconds: 30, check_interval_seconds: 15, path: '/' }

  # Redis TTL configuration (in seconds)
  config.redis_ttl = { rate: 310, default: 3600 }  # 5 minutes 10 seconds for rates, 1 hour default



end


