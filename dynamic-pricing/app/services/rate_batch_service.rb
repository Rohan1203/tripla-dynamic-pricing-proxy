require 'net/http'
require 'json'

class RateBatchService

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

  def retry_backoff
    Rails.application.config.retry[:backoff] || 0
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

    self.logger.info("Sending rate retrieval request to #{host} with #{payload[:attributes].size} items")

    max_retries = retry_count.to_i
    base_backoff = retry_backoff.to_i

    retries = 0
    begin
      http.request(request)
    rescue StandardError => e
      if retries < max_retries
        wait_time = base_backoff * (2**retries)
        self.logger.warn("Request failed: #{e.message}. Retrying in #{wait_time} seconds (Attempt #{retries + 1}/#{max_retries})")
        sleep wait_time
        retries += 1
        retry
      else
        self.logger.error("Failed to connect to rate API after #{max_retries} retries: #{e.message}")
        nil
      end
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
      
      # Store rates in Redis using RedisService
      if rates && !rates.empty?
        success = RedisService.store_rates(rates)
        if success
          self.logger.info("Successfully stored #{rates.size} rates in Redis")
        else
          self.logger.error("Failed to store rates in Redis")
        end
      else
        self.logger.warn("No rates to store in Redis")
      end
      
      # Log individual rates in debug mode
      rates&.each do |rate|
        self.logger.debug({ rate: rate })
      end
    else
      self.logger.error("API request failed with status #{response.code}: #{response.body}")
    end
  end
end
