require "active_support/core_ext/integer/time"

# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with Cache-Control for performance.
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    "Cache-Control" => "public, max-age=#{1.hour.to_i}"
  }

  # Show full error reports and disable caching.
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions
  config.action_controller.raise_on_missing_callback_actions = true

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
  config.rate_api = { host: "http://localhost:8080/pricing", token: "" }
  config.retry = { count: 1, backoff: 0 }
  config.batch = { interval: 5 }

  # Redis TTL configuration (in seconds)
  config.redis_ttl = { rate: 310, default: 3600 }  # 5 minutes for rates, 1 hour default


end
