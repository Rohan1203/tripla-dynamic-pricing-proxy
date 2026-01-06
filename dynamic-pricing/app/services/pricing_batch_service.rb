require 'net/http'
require 'json'

# PricingBatchService handles batch operations for fetching and processing pricing rates.
# It constructs payloads based on predefined periods, hotels, and rooms,
# sends HTTP requests to the rate API with retry logic, and processes the responses.
# This service is designed for bulk pricing data retrieval and includes logging capabilities.
class PricingBatchService

  PERIODS = ["Summer", "Autumn", "Winter", "Spring"].freeze
  HOTELS = ["FloatingPointResort", "GitawayHotel", "RecursionRetreat"].freeze
  ROOMS = ["SingletonRoom", "BooleanTwin", "RestfulKing"].freeze

  def self.logger
    Rails.application.config.logger
  end

  def logger
    self.class.logger
  end

  def self.call
    new.call
  end

  def call
    payload = build_payload
    response = send_request_with_retry(payload)
    if response && response.code == '500'
      sleep 1
      response = send_request_with_retry(payload)
    end
    item_process_response(response)
  end

  private

  def rate_api_host
    Rails.application.config.rate_api[:host]
  end

  def rate_api_token
    Rails.application.config.rate_api[:token]
  end

  def retry_count
    Rails.application.config.retry[:count] || 0
  end

  def retry_base_backoff
    Rails.application.config.retry[:base_backoff_seconds] || 1
  end

  def retry_multiplier
    Rails.application.config.retry[:backoff_multiplier] || 2
  end

  def retry_max_backoff
    Rails.application.config.retry[:max_backoff_seconds] || 30
  end

  def build_payload
    attributes = []
    PERIODS.each do |period|
      HOTELS.each do |hotel|
        ROOMS.each do |room|
          attributes << { period: period, hotel: hotel, room: room }
        end
      end
    end
    { attributes: attributes }
  end

  def send_request_with_retry(payload)
    host = rate_api_host
    token = rate_api_token

    if host.nil? || host.empty?
      self.logger.error("Rate API host is not configured. Check config/rate_retriever.yml under rate_api.host")
      return nil
    end

    uri = URI(host)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['token'] = token if token.present?
    request.body = payload.to_json

    self.logger.debug("Sending rate retrieval request to #{host} with #{payload[:attributes].size} items")

    max_retries = retry_count.to_i
    base_backoff = retry_base_backoff.to_i
    multiplier = retry_multiplier.to_i

    # Compute a longer backoff between cycles of attempts. After performing
    # `max_retries` attempts (with exponential backoff within the cycle), we
    # wait this cycle backoff and then perform another cycle. This repeats
    # continuously until a successful 200 response is received.
    cycle_backoff = base_backoff * (multiplier**[max_retries, 1].max)

    loop do
      attempts = 0

      while attempts < max_retries
        begin
          resp = http.request(request)

          if resp && resp.code.to_i == 200
            return resp
          end

          attempts += 1
          if attempts < max_retries
            wait_time = base_backoff * (multiplier**(attempts - 1))
            self.logger.error("API request returned #{resp&.code}. Retrying in #{wait_time} seconds (Attempt #{attempts}/#{max_retries})")
            sleep wait_time
            next
          else
            self.logger.error("Cycle of #{max_retries} attempts failed (last status #{resp&.code}). Backing off #{cycle_backoff} seconds before next cycle")
          end

        rescue StandardError => e
          attempts += 1
          if attempts < max_retries
            wait_time = base_backoff * (multiplier**(attempts - 1))
            self.logger.error("Request failed: #{e.message}. Retrying in #{wait_time} seconds (Attempt #{attempts}/#{max_retries})")
            sleep wait_time
            next
          else
            self.logger.error("Cycle of #{max_retries} attempts failed due to errors: #{e.message}. Backing off #{cycle_backoff} seconds before next cycle")
          end
        end
      end

      sleep cycle_backoff
    end
  end

  def item_process_response(response)
    return unless response

    if response.code == '500'
      self.logger.error("There is some trouble while retrieved rates. #{response}")
    end
    if response.code == '200'
      data = JSON.parse(response.body)
      rates = data['rates']
      
      self.logger.info("Successfully retrieved rates. Count: #{rates&.size}")
      
      # Store rates in Redis using RedisService (always synchronous so cache is hot)
      if rates && !rates.empty?
        success = RedisService.store_rates(rates)
        if success
          self.logger.info("Successfully stored #{rates.size} rates in Redis")
        else
          self.logger.error("Failed to store rates in Redis")
        end

        # Persist batch into relational DB asynchronously for historical use
        begin
          persist_rates_to_db(rates)
        rescue StandardError => e
          self.logger.error("Failed to enqueue persistence of rates to historical DB: #{e.class} - #{e.message}")
        end
      else
        self.logger.warn("No rates to store in Redis or DB")
      end
      
      # Log individual rates in debug mode
      rates&.each do |rate|
        self.logger.debug({ rate: rate })
      end
    else
      self.logger.error("API request failed with status #{response.code}: #{response.body}")
    end
  end

  def persist_rates_to_db(rates)
    return unless defined?(HistoricalRate)

    count = Array(rates).size
    self.logger.debug("[pricing] enqueueing PersistHistoricalRatesJob for #{count} rate(s)")
    PersistHistoricalRatesJob.perform_later(rates)
  end
end
