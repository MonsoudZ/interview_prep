require "minitest/autorun"
require_relative "../solution"

class VisibleRateLimiterTest < Minitest::Test
  def test_allows_up_to_the_limit
    limiter = RateLimiter.new(limit: 3, window_seconds: 60)
    assert_equal [true, true, true], 3.times.map { |i| limiter.allow?(:user, i) }
  end
  def test_rejects_beyond_the_limit_inside_the_window
    limiter = RateLimiter.new(limit: 2, window_seconds: 60)
    limiter.allow?(:user, 0)
    limiter.allow?(:user, 1)
    assert_equal false, limiter.allow?(:user, 30)
  end
  def test_requests_expire_after_the_window
    limiter = RateLimiter.new(limit: 2, window_seconds: 10)
    limiter.allow?(:user, 0)
    limiter.allow?(:user, 5)
    assert_equal false, limiter.allow?(:user, 9.9)
    assert_equal true, limiter.allow?(:user, 10)
  end
  def test_keys_are_independent
    limiter = RateLimiter.new(limit: 1, window_seconds: 60)
    assert_equal true, limiter.allow?(:alice, 0)
    assert_equal true, limiter.allow?(:bob, 0)
    assert_equal false, limiter.allow?(:alice, 1)
  end
  def test_remaining_reports_without_recording
    limiter = RateLimiter.new(limit: 3, window_seconds: 60)
    assert_equal 3, limiter.remaining(:user, 0)
    limiter.allow?(:user, 0)
    assert_equal 2, limiter.remaining(:user, 1)
    assert_equal 2, limiter.remaining(:user, 1)
  end
  def test_arguments_are_validated
    assert_raises(ArgumentError) { RateLimiter.new(limit: 0, window_seconds: 60) }
    assert_raises(ArgumentError) { RateLimiter.new(limit: 1, window_seconds: 0) }
    assert_raises(ArgumentError) { RateLimiter.new(limit: "2", window_seconds: 60) }
  end
end
