require 'test_helper'
require 'ostruct'

class RateHealthMonitorTest < ActiveSupport::TestCase
  def setup
    @host = 'http://localhost:8080/pricing'
    # preserve original config and set test-specific value
    @orig_rate_api = Rails.application.config.rate_api.dup rescue nil
    Rails.application.config.rate_api = { host: @host, token: 'token' }
  end

  def teardown
    # restore original config to avoid leaking state between tests
    if defined?(@orig_rate_api) && @orig_rate_api
      Rails.application.config.rate_api = @orig_rate_api
    end
  end

  test 'check_upstream treats non-5xx as healthy' do
    fake_response = OpenStruct.new(code: '405')

    fake_http = Object.new
    def fake_http.open_timeout=(_); end
    def fake_http.read_timeout=(_); end
    def fake_http.request(_req)
      OpenStruct.new(code: '405')
    end

    Net::HTTP.singleton_class.define_method(:new) do |host, port|
      fake_http
    end

    healthy = Helpers::RateHealthMonitor.send(:check_upstream)
    assert_equal true, healthy
  ensure
    # remove the singleton override to avoid leaking into other tests
    Net::HTTP.singleton_class.send(:remove_method, :new) if Net::HTTP.singleton_class.method_defined?(:new)
  end

  test 'check_upstream returns false on exception' do
    Net::HTTP.singleton_class.define_method(:new) do |host, port|
      raise Errno::ECONNREFUSED.new('Connection refused')
    end

    healthy = Helpers::RateHealthMonitor.send(:check_upstream)
    assert_equal false, healthy
  ensure
    Net::HTTP.singleton_class.send(:remove_method, :new) if Net::HTTP.singleton_class.method_defined?(:new)
  end
end
