# Trusted supplemental practice checks. Fixtures are omitted from the editor, not secret from sandbox code.
require "minitest/autorun"
class AdditionalRateLimiterTest < Minitest::Test
  def test_exact_window_boundary
    limiter = RateLimiter.new(limit: 1, window_seconds: 10)
    limiter.allow?(:k, 100)
    assert limiter.allow?(:k, 109.999) == false && limiter.allow?(:k, 110) == true, "Boundary contract failed: expiry is at exactly window_seconds"
  end
  def test_rejected_requests_are_not_recorded
    limiter = RateLimiter.new(limit: 2, window_seconds: 10)
    limiter.allow?(:k, 0)
    limiter.allow?(:k, 1)
    5.times { |i| limiter.allow?(:k, 2 + i) }
    assert limiter.allow?(:k, 10) == true && limiter.allow?(:k, 10.5) == false && limiter.allow?(:k, 11) == true, "Rejected requests must not consume capacity"
  end
  def test_equal_timestamps_and_float_times
    limiter = RateLimiter.new(limit: 3, window_seconds: 0.5)
    results = 4.times.map { limiter.allow?("same", 1.25) }
    assert results == [true, true, true, false] && limiter.allow?("same", 1.75) == true, "Equal/float timestamp contract failed"
  end
  def test_generated_sequences_match_an_independent_oracle
    random = Random.new(31415)
    40.times do
      limit, window = random.rand(1..4), random.rand(1..6)
      limiter = RateLimiter.new(limit: limit, window_seconds: window)
      log = Hash.new { |h, k| h[k] = [] } # every accepted timestamp, never pruned
      clock = Hash.new(0)
      200.times do
        key = random.rand(0..2)
        clock[key] += random.rand(0..3)
        now = clock[key]
        expected = log[key].count { |t| now - t < window } < limit
        assert limiter.remaining(key, now) == [limit - log[key].count { |t| now - t < window }, 0].max, "Generated remaining diverged from the oracle"
        log[key] << now if expected
        assert limiter.allow?(key, now) == expected, "Generated allow? diverged from the oracle"
      end
    end
  end
  def test_one_hundred_thousand_calls_on_one_key_stay_bounded
    limiter = RateLimiter.new(limit: 5, window_seconds: 2)
    accepted = 0
    100_000.times { |i| accepted += 1 if limiter.allow?(:hot, i * 0.1) }
    assert accepted == 25_002 || accepted.between?(24_990, 25_010), "Large sequence must stay bounded and accept about one in four requests (#{accepted})"
  end
  def test_many_keys_do_not_interfere
    limiter = RateLimiter.new(limit: 1, window_seconds: 100)
    10_000.times { |i| assert limiter.allow?(i, 0) == true, "First request per key must be allowed" }
    assert limiter.allow?(42, 50) == false && limiter.allow?(10_001, 50) == true, "Keys must be isolated"
  end
end
