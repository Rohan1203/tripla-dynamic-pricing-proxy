require 'test_helper'

class CircuitBreakerTest < ActiveSupport::TestCase
  def setup
    # ensure fresh instance map by using a unique name
    @name = "test_cb_#{Time.now.to_i}_#{rand(1000)}"
    @cb = Helpers::CircuitBreaker.for(name: @name, threshold: 2, open_ttl: 30, probe_interval: 1)
  end

  test 'for returns same instance for same name' do
    cb2 = Helpers::CircuitBreaker.for(name: @name)
    assert_equal @cb.object_id, cb2.object_id
  end

  test 'records failures and opens when threshold reached' do
    @cb.reset
    assert_equal false, @cb.open?

    @cb.record_failure
    assert_equal false, @cb.open?

    @cb.record_failure
    assert_equal true, @cb.open?
  end

  test 'record_success closes the circuit' do
    @cb.record_failure
    @cb.record_failure
    assert @cb.open?
    @cb.record_success
    assert_equal false, @cb.open?
  end

  test 'reset clears state' do
    @cb.record_failure
    @cb.record_failure
    assert @cb.open?
    @cb.reset
    assert_equal false, @cb.open?
  end
end
