module RateAttributes
  module_function

  # Extract a canonical rate value from various possible keys
  def extract_rate_value(attrs)
    return nil if attrs.nil?

    if attrs.is_a?(Hash)
      attrs[:rate] || attrs['rate'] ||
        attrs[:price] || attrs['price'] ||
        attrs[:value] || attrs['value']
    else
      nil
    end
  end

  # Unified payload structure used by the /pricing API
  def build_payload(period:, hotel:, room:, rate:)
    {
      'period' => period,
      'hotel'  => hotel,
      'room'   => room,
      'rate'   => rate.to_s
    }
  end
end
