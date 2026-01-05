require "test_helper"

class PersistHistoricalRatesJobTest < ActiveJob::TestCase
  test "inserts a batch of rates into HistoricalRate" do
    rates = [
      { "period" => "Summer", "hotel" => "FloatingPointResort", "room" => "SingletonRoom", "rate" => "12000" },
      { "period" => "Winter", "hotel" => "GitawayHotel",        "room" => "BooleanTwin",  "rate" => "9000" }
    ]

    assert_difference -> { HistoricalRate.count }, +2 do
      perform_enqueued_jobs do
        PersistHistoricalRatesJob.perform_later(rates)
      end
    end
  end
end
