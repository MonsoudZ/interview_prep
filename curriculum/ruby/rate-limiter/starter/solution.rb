class RateLimiter
  def initialize(limit:, window_seconds:)
    # Implement the published contract.
  end

  def allow?(key, now)
  end

  def remaining(key, now)
  end
end
