# Service exposed to clients to return pricing for a single combination.
# Lookup strategy with coalescing and DB freshness:
# 1) Redis cache (hit/miss)
# 2) On miss, check latest SQLite historical row:
#    - if < 30s old, use it directly (no API call)
#    - if >= 30s old, return it but trigger an async batch refresh
# 3) If there is NO Redis AND NO DB:
#    - perform a synchronous batch API call (PricingBatchService.call)
#    - re-check Redis/DB and return if data is now present
# 4) If still nothing, raise RateNotFoundError
class PricingService
  class RateNotFoundError < StandardError; end

  class << self
    def call(period:, hotel:, room:)
      new(period: period, hotel: hotel, room: room).call
    end

    # Multi-rate entrypoint.
    # Flow per requested combination:
    # 1) Try Redis first; if hit, use it.
    # 2) Else, check DB within freshness window; if hit, use it.
    # 3) Collect only the remaining (truly missing) combinations and call upstream once.
    # 4) Build response from a mix of Redis / DB / upstream results and return immediately.
    #    Upstream service is responsible for async writes to Redis/DB.
    def call_many(rates:)
      attributes = Array(rates).map do |r|
        {
          period: r[:period] || r["period"],
          hotel:  r[:hotel]  || r["hotel"],
          room:   r[:room]   || r["room"]
        }
      end

      # Map from key -> response payload
      results = {}
      missing_for_upstream = []

      attributes.each do |attr|
        period = attr[:period]
        hotel  = attr[:hotel]
        room   = attr[:room]
        key    = [period, hotel, room].join("|")

        # 1) Redis
        redis_rate = RedisService.get_rate(period: period, hotel: hotel, room: room)
        if redis_rate
          results[key] = RateAttributes.build_payload(
            period: period,
            hotel:  hotel,
            room:   room,
            rate:   RateAttributes.extract_rate_value(redis_rate)
          )
          next
        end

        # 2) DB (fresh within window)
        db_record = HistoricalRate
          .where(period: period, hotel: hotel, room: room)
          .where("retrieved_at >= ?", Time.current - db_max_age_seconds)
          .order(retrieved_at: :desc)
          .first

        if db_record
          results[key] = RateAttributes.build_payload(
            period: db_record.period,
            hotel:  db_record.hotel,
            room:   db_record.room,
            rate:   db_record.rate
          )
          next
        end

        # 3) Truly missing – will be sent to upstream
        missing_for_upstream << attr
      end

      upstream_rates = if missing_for_upstream.any?
                         PricingUpstreamService.fetch_rates(missing_for_upstream)
                       else
                         []
                       end

      # Index upstream results for quick lookup
      upstream_index = {}
      upstream_rates.each do |r|
        p = r["period"] || r[:period]
        h = r["hotel"]  || r[:hotel]
        rm = r["room"]  || r[:room]
        upstream_index[[p, h, rm].join("|")] = r
      end

      # Build final array in the same order as input
      attributes.map do |attr|
        key   = [attr[:period], attr[:hotel], attr[:room]].join("|")
        found = results[key]

        if found
          found
        else
          r = upstream_index[key]
          RateAttributes.build_payload(
            period: attr[:period],
            hotel:  attr[:hotel],
            room:   attr[:room],
            rate:   RateAttributes.extract_rate_value(r)
          )
        end
      end
    end
  end

  def initialize(period:, hotel:, room:)
    @period = period
    @hotel  = hotel
    @room   = room
  end

  def call
    # 1) Redis first
    rate = RedisService.get_rate(period: @period, hotel: @hotel, room: @room)
    if rate
      Rails.logger.info("[pricing] cache HIT for period=#{@period}, hotel=#{@hotel}, room=#{@room}")
      return normalize_cache_rate(rate)
    end

    Rails.logger.info("[pricing] cache MISS for period=#{@period}, hotel=#{@hotel}, room=#{@room}")

    # 2) Latest DB record
    db_record = latest_historical
    if db_record
      if fresh_db_record?(db_record)
        Rails.logger.info("[pricing] historical DB HIT (fresh) for period=#{@period}, hotel=#{@hotel}, room=#{@room}")
        return normalize_record(db_record)
      else
        Rails.logger.info("[pricing] historical DB HIT (STALE) for period=#{@period}, hotel=#{@hotel}, room=#{@room}; triggering async refresh")
        trigger_async_refresh
        return normalize_record(db_record)
      end
    end

    # 3) No Redis AND no DB: call upstream only for this combination and return immediately
    Rails.logger.info("[pricing] no Redis or DB data; calling upstream for single combination period=#{@period}, hotel=#{@hotel}, room=#{@room}")

    upstream_rates = PricingUpstreamService.fetch_rates([
      { period: @period, hotel: @hotel, room: @room }
    ])

    if upstream_rates.any?
      # Find exact match or fall back to first result
      rate_hash = upstream_rates.find do |r|
        (r["period"] || r[:period]) == @period &&
          (r["hotel"]  || r[:hotel])  == @hotel &&
          (r["room"]   || r[:room])   == @room
      end || upstream_rates.first

      return normalize_cache_rate(rate_hash)
    end

    Rails.logger.warn("[pricing] no rate found from upstream for period=#{@period}, hotel=#{@hotel}, room=#{@room}")
    raise RateNotFoundError, "Rate is not available yet for the requested combination"
  rescue RedisService::RedisError => e
    Rails.logger.error("Redis failure while retrieving rate: #{e.class} - #{e.message}")
    raise
  end

  private

  def trigger_async_refresh
    unless can_refresh_now?
      Rails.logger.debug("[pricing] skipping async refresh due to coalescing window for period=#{@period}, hotel=#{@hotel}, room=#{@room}")
      return
    end

    Rails.logger.debug("[pricing] starting async refresh thread for period=#{@period}, hotel=#{@hotel}, room=#{@room}")
    Thread.new do
      begin
        PricingBatchService.call
        Rails.logger.info("[pricing] async refresh completed for period=#{@period}, hotel=#{@hotel}, room=#{@room}")
      rescue StandardError => e
        Rails.logger.error("[pricing] async refresh failed: #{e.class} - #{e.message}")
      end
    end
  end

  def can_refresh_now?
    last_updated = RedisService.get('rates:last_updated')
    if last_updated.nil?
      Rails.logger.debug("[pricing] can_refresh_now? => true (no rates:last_updated in Redis)")
      return true
    end

    age     = Time.current.to_i - last_updated.to_i
    allowed = age > refresh_window_seconds

    if allowed
      Rails.logger.info("[pricing] refresh allowed by coalescing window; last_updated_age=#{age}s threshold=#{refresh_window_seconds}s")
    else
      Rails.logger.warn("[pricing] refresh suppressed by coalescing window; last_updated_age=#{age}s threshold=#{refresh_window_seconds}s")
    end

    allowed
  end

  def latest_historical
    return nil unless defined?(HistoricalRate)

    Rails.logger.debug("[pricing] querying historical DB for period=#{@period}, hotel=#{@hotel}, room=#{@room}")

    record = HistoricalRate
      .where(period: @period, hotel: @hotel, room: @room)
      .order(retrieved_at: :desc)
      .first

    if record
      age = Time.current - record.retrieved_at
      Rails.logger.debug("[pricing] latest historical DB record age=#{age.round(3)}s for period=#{@period}, hotel=#{@hotel}, room=#{@room}")
    else
      Rails.logger.debug("[pricing] no historical DB record found for period=#{@period}, hotel=#{@hotel}, room=#{@room}")
    end

    record
  rescue StandardError => e
    Rails.logger.error("[pricing] error while querying historical DB: #{e.class} - #{e.message}")
    nil
  end

  def fresh_db_record?(record)
    age   = Time.current - record.retrieved_at
    fresh = age <= db_max_age_seconds

    Rails.logger.debug(
      "[pricing] historical DB record freshness check age=#{age.round(3)}s " \
      "threshold=#{db_max_age_seconds}s fresh=#{fresh} for period=#{@period}, hotel=#{@hotel}, room=#{@room}"
    )

    fresh
  end

  def db_max_age_seconds
    (Rails.application.config.respond_to?(:pricing) &&
      Rails.application.config.pricing[:db_max_age_seconds]).to_i.nonzero? || 30
  end

  def refresh_window_seconds
    (Rails.application.config.respond_to?(:pricing) &&
      Rails.application.config.pricing[:refresh_window_seconds]).to_i.nonzero? || 5
  end

  def normalize_cache_rate(raw_rate)
    value = RateAttributes.extract_rate_value(raw_rate)

    RateAttributes.build_payload(
      period: raw_rate["period"] || @period,
      hotel:  raw_rate["hotel"]  || @hotel,
      room:   raw_rate["room"]   || @room,
      rate:   value
    )
  end

  def normalize_record(record)
    RateAttributes.build_payload(
      period: record.period,
      hotel:  record.hotel,
      room:   record.room,
      rate:   record.rate
    )
  end
end
