class PricingController < ApplicationController
  VALID_PERIODS = %w[Summer Autumn Winter Spring].freeze
  VALID_HOTELS  = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  VALID_ROOMS   = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  before_action :normalize_params
  before_action :validate_params, unless: -> { @rates.present? }

  def index
    if @rates.present?
      # Multi-rate request mode
      rates = PricingService.call_many(rates: @rates)
      render json: { timestamp: response_timestamp, rates: rates }, status: :ok
      return
    end

    # Single-rate request mode
    rate = PricingService.call(
      period: @period,
      hotel:  @hotel,
      room:   @room
    )

    render json: rate.merge(timestamp: response_timestamp), status: :ok
  rescue PricingService::RateNotFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue RedisService::RedisError => e
    Rails.logger.error("Redis error while handling /pricing: #{e.class} - #{e.message}")
    render json: { error: "Temporary error while retrieving rate", timestamp: response_timestamp }, status: :service_unavailable
  end

  private

  # ---- NEW: normalize once, use everywhere ----
  def normalize_params
    @period = params[:period] || params["period"]
    @hotel  = params[:hotel]  || params["hotel"]
    @room   = params[:room]   || params["room"]

    @rates =
      if params[:rates].present?
        Array(params[:rates]).map do |r|
          {
            period: r[:period] || r["period"],
            hotel:  r[:hotel]  || r["hotel"],
            room:   r[:room]   || r["room"]
          }
        end
      end
  end

  def validate_params
    unless @period.present? && @hotel.present? && @room.present?
      return render json: { error: "Missing required parameters: period, hotel, room" }, status: :bad_request
    end

    unless VALID_PERIODS.include?(@period)
      return render json: { error: "Invalid period. Must be one of: #{VALID_PERIODS.join(', ')}" }, status: :bad_request
    end

    unless VALID_HOTELS.include?(@hotel)
      return render json: { error: "Invalid hotel. Must be one of: #{VALID_HOTELS.join(', ')}" }, status: :bad_request
    end

    unless VALID_ROOMS.include?(@room)
      return render json: { error: "Invalid room. Must be one of: #{VALID_ROOMS.join(', ')}" }, status: :bad_request
    end
  end

  # return current timestamp
  def response_timestamp
    Time.current.utc.iso8601
  end
end
