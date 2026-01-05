
# PersistHistoricalRatesJob is a background job that handles the persistence of historical pricing rates.
# It processes an array of rate data, extracts relevant attributes using RateAttributes,
# and inserts them into the HistoricalRate model in the database.
# This job is queued in the default queue and includes logging for monitoring and debugging purposes.
class PersistHistoricalRatesJob < ApplicationJob
  queue_as :default

  def perform(rates)
    return unless defined?(HistoricalRate)

    rates_array = Array(rates)
    Rails.logger.info("[pricing] PersistHistoricalRatesJob persisting #{rates_array.size} rate(s) to DB")

    now = Time.current

    payload = rates_array.map do |rate|
      value = RateAttributes.extract_rate_value(rate)

      {
        period:       rate['period'] || rate[:period],
        hotel:        rate['hotel']  || rate[:hotel],
        room:         rate['room']   || rate[:room],
        rate:         value.to_s,
        retrieved_at: now,
        created_at:   now,
        updated_at:   now
      }
    end

    if payload.any?
      HistoricalRate.insert_all(payload)
      Rails.logger.debug("[pricing] PersistHistoricalRatesJob inserted #{payload.size} historical rate row(s)")
    else
      Rails.logger.warn("[pricing] PersistHistoricalRatesJob received empty rates payload; nothing to insert")
    end
  end
end
