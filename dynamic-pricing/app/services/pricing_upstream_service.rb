require 'net/http'
require 'json'

class PricingUpstreamService
  class << self
    # attributes: array of hashes with keys :period, :hotel, :room
    # returns: array of raw rate hashes as returned by upstream (or empty array on failure)
    def fetch_rates(attributes)
      new(attributes).call
    end
  end

  def initialize(attributes)
    @attributes = Array(attributes)
  end

  def call
    return [] if @attributes.empty?

    payload = { attributes: @attributes.map { |a| normalize_attr(a) } }

    response = send_request(payload)
    return [] unless response && response.code.to_s == '200'

    data  = JSON.parse(response.body)
    rates = data['rates'] || []

    schedule_async_cache_writes(rates)

    rates
  rescue StandardError => e
    Rails.logger.error("[pricing] PricingUpstreamService failed: #{e.class} - #{e.message}")
    []
  end

  private

  def normalize_attr(raw)
    {
      period: raw[:period] || raw['period'],
      hotel:  raw[:hotel]  || raw['hotel'],
      room:   raw[:room]   || raw['room']
    }
  end

  def send_request(payload)
    host  = Rails.application.config.rate_api[:host]
    token = Rails.application.config.rate_api[:token]

    # Circuit breaker integration (use Helpers::CircuitBreaker.for)
    cb = Helpers::CircuitBreaker.for(
      name: 'pricing_upstream',
      threshold: (Rails.application.config.respond_to?(:upstream_health_check) && Rails.application.config.upstream_health_check[:failure_threshold]) || 5,
      open_ttl: (Rails.application.config.respond_to?(:upstream_health_check) && Rails.application.config.upstream_health_check[:open_ttl_seconds]) || 60,
      probe_url: Rails.application.config.rate_api[:host],
      probe_interval: (Rails.application.config.respond_to?(:upstream_health_check) && Rails.application.config.upstream_health_check[:check_interval_seconds]) || 10
    )

    unless cb.allow?
      Rails.logger.warn("[pricing] Circuit open for upstream requests; skipping HTTP call")
      return nil
    end

    if host.nil? || host.empty?
      Rails.logger.error("[pricing] PricingUpstreamService: rate_api.host is not configured")
      return nil
    end

    uri  = URI(host)
    http = Net::HTTP.new(uri.host, uri.port)
    req  = Net::HTTP::Post.new(uri.path)
    req['Content-Type'] = 'application/json'
    req['token']        = token if token.present?
    req.body            = payload.to_json

    Rails.logger.info("[pricing] PricingUpstreamService sending request to #{host} for #{@attributes.size} attribute set(s)")

    resp = http.request(req)
    if resp && resp.code.to_i >= 200 && resp.code.to_i < 500
      cb.record_success
    else
      cb.record_failure
    end
    resp
  rescue StandardError => e
    Rails.logger.error("[pricing] PricingUpstreamService HTTP error: #{e.class} - #{e.message}")
    cb.record_failure rescue nil
    nil
  end

  # After we have the response, write to Redis and DB asynchronously so we can
  # return to the caller as fast as possible.
  def schedule_async_cache_writes(rates)
    return if rates.nil? || rates.empty?

    Thread.new do
      begin
        # Redis write (best-effort)
        if RedisService.store_rates(rates)
          Rails.logger.info("[pricing] PricingUpstreamService asynchronously stored #{rates.size} rate(s) in Redis")
        else
          Rails.logger.warn("[pricing] PricingUpstreamService failed to store rates in Redis")
        end

        # DB persistence via existing job (best-effort)
        if defined?(PersistHistoricalRatesJob)
          PersistHistoricalRatesJob.perform_later(rates)
          Rails.logger.debug("[pricing] PricingUpstreamService enqueued PersistHistoricalRatesJob for #{rates.size} rate(s)")
        end
      rescue StandardError => e
        Rails.logger.error("[pricing] PricingUpstreamService async cache write failure: #{e.class} - #{e.message}")
      end
    end
  end
end
