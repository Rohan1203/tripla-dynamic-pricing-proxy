class HistoricalRate < ApplicationRecord
  validates :period, :hotel, :room, :rate, :retrieved_at, presence: true

  scope :recent_for, lambda { |period:, hotel:, room:, window_seconds: 30|
    where(period: period, hotel: hotel, room: room)
      .where("retrieved_at >= ?", Time.current - window_seconds)
      .order(retrieved_at: :desc)
  }
end
