require 'net/http'
require 'json'

class RateRetrieverService

  PERIODS = ["Summer", "Autumn", "Winter", "Spring"].freeze
  HOTELS = ["FloatingPointResort", "GitawayHotel", "RecursionRetreat"].freeze
  ROOMS = ["SingletonRoom", "BooleanTwin", "RestfulKing"].freeze

  def self.call
    new.call
  end

  def call
    payload = build_payload
    response = send_request_with_retry(payload)
    item_process_response(response)
  end

  private

  def config
    ConfigManager[:rate_retriever] || {}
  end

  def rate_api_host
    config.dig(:rate_api, :host)
  end

  def rate_api_token
    config.dig(:rate_api, :token)
  end

  def retry_count
    config.dig(:retry, :count) || 0
  end

  def retry_backoff
    config.dig(:retry, :backoff) || 0
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
      Rails.logger.error("Rate API host is not configured. Check config/rate_retriever.yml under rate_api.host")
      return nil
    end

    uri = URI(host)
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['token'] = token if token.present?
    request.body = payload.to_json

    Rails.logger.info("Sending rate retrieval request to #{host} with #{payload[:attributes].size} items")

    max_retries = retry_count.to_i
    base_backoff = retry_backoff.to_i

    retries = 0
    begin
      http.request(request)
    rescue StandardError => e
      if retries < max_retries
        wait_time = base_backoff * (2**retries)
        Rails.logger.warn("Request failed: #{e.message}. Retrying in #{wait_time} seconds (Attempt #{retries + 1}/#{max_retries})")
        sleep wait_time
        retries += 1
        retry
      else
        Rails.logger.error("Failed to connect to rate API after #{max_retries} retries: #{e.message}")
        nil
      end
    end
  end

  def item_process_response(response)
    return unless response

    if response.code == '200'
      data = JSON.parse(response.body)
      Rails.logger.info("Successfully retrieved rates. Count: #{data['rates']&.size}")
      # In a real app, we would likely save these rates to the DB here.
      # For now, just logging as requested.
      data['rates']&.each do |rate|
         Rails.logger.debug("Rate: #{rate.inspect}")
      end
    else
      Rails.logger.error("API request failed with status #{response.code}: #{response.body}")
    end
  end
end
