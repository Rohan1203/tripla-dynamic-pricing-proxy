class CreateHistoricalRates < ActiveRecord::Migration[7.1]
  def change
    create_table :historical_rates do |t|
      t.string   :period,       null: false
      t.string   :hotel,        null: false
      t.string   :room,         null: false
      t.string   :rate,         null: false
      t.datetime :retrieved_at, null: false

      t.timestamps
    end

    add_index :historical_rates, [:period, :hotel, :room, :retrieved_at], name: "idx_historical_rates_on_keys_and_time"
  end
end
