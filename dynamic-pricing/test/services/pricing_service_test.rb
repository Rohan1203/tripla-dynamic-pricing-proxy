require "test_helper"

class PricingServiceTest < ActiveSupport::TestCase
  def setup
    @period = "Summer"
    @hotel  = "FloatingPointResort"
    @room   = "SingletonRoom"
  end

  test "returns rate from Redis on cache hit without calling upstream" do
    redis_rate = {
      "period" => @period,
      "hotel"  => @hotel,
      "room"   => @room,
      "rate"   => "12000"
    }

    RedisService.stub(:get_rate, redis_rate) do
      PricingUpstreamService.stub(:fetch_rates, ->(*) { flunk "upstream should not be called on cache hit" }) do
        result = PricingService.call(period: @period, hotel: @hotel, room: @room)

        assert_equal @period, result["period"]
        assert_equal @hotel,  result["hotel"]
        assert_equal @room,   result["room"]
        assert_equal "12000", result["rate"]
      end
    end
  end

  test "on cache miss and no DB calls upstream once and returns rate from upstream" do
    # Redis miss
    RedisService.stub(:get_rate, nil) do
      # No DB rows
      HistoricalRate.stub(:where, ->(*) { HistoricalRate.none }) do
        upstream_rates = [
          { "period" => @period, "hotel" => @hotel, "room" => @room, "rate" => "13000" }
        ]

        PricingUpstreamService.stub(:fetch_rates, upstream_rates) do
          result = PricingService.call(period: @period, hotel: @hotel, room: @room)
          assert_equal "13000", result["rate"]
        end
      end
    end
  end

  test "on cache miss and fresh DB record returns DB value without calling upstream" do
    # Ensure DB has a fresh historical record for this combination
    HistoricalRate.delete_all
    HistoricalRate.create!(
      period:       @period,
      hotel:        @hotel,
      room:         @room,
      rate:         "14000",
      retrieved_at: Time.current
    )

    RedisService.stub(:get_rate, nil) do
      PricingUpstreamService.stub(:fetch_rates, ->(*) { flunk "upstream should not be called when fresh DB record exists" }) do
        result = PricingService.call(period: @period, hotel: @hotel, room: @room)

        assert_equal "14000", result["rate"]
      end
    end
  end
end
