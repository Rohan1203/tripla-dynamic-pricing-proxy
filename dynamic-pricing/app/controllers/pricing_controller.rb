class PricingController < ApplicationController
  VALID_PERIODS = %w[Summer Autumn Winter Spring].freeze
  VALID_HOTELS = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  VALID_ROOMS = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  before_action :validate_params, unless: -> { params[:rates].present? }

  def index
    if params[:rates].present?
      # Multi-rate request mode
      requests = Array(params[:rates]).map do |rate_params|
        {
          period: rate_params[:period] || rate_params["period"],
          hotel:  rate_params[:hotel]  || rate_params["hotel"],
          room:   rate_params[:room]   || rate_params["room"]
        }
      end

      rates = PricingService.call_many(rates: requests)
      render json: { rates: rates }, status: :ok
      return
    end

    # Single-rate request mode
    period = params[:period]
    hotel  = params[:hotel]
    room   = params[:room]

    rate = PricingService.call(period: period, hotel: hotel, room: room)

    render json: rate, status: :ok
  rescue PricingService::RateNotFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue RedisService::RedisError => e
    Rails.logger.error("Redis error while handling /pricing: #{e.class} - #{e.message}")
    render json: { error: "Temporary error while retrieving rate" }, status: :service_unavailable
  end

  private

  def validate_params
    # Validate required parameters
    unless params[:period].present? && params[:hotel].present? && params[:room].present?
      return render json: { error: "Missing required parameters: period, hotel, room" }, status: :bad_request
    end

    # Validate parameter values
    unless VALID_PERIODS.include?(params[:period])
      return render json: { error: "Invalid period. Must be one of: #{VALID_PERIODS.join(', ')}" }, status: :bad_request
    end

    unless VALID_HOTELS.include?(params[:hotel])
      return render json: { error: "Invalid hotel. Must be one of: #{VALID_HOTELS.join(', ')}" }, status: :bad_request
    end

    unless VALID_ROOMS.include?(params[:room])
      return render json: { error: "Invalid room. Must be one of: #{VALID_ROOMS.join(', ')}" }, status: :bad_request
    end
  end
end
