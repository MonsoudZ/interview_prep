class RateLimiter
  def initialize(limit:, window_seconds:)
    unless limit.is_a?(Integer) && limit >= 1 && window_seconds.is_a?(Numeric) && window_seconds > 0
      raise ArgumentError, "limit must be a positive integer and window_seconds a positive number"
    end
    @limit = limit
    @window = window_seconds
    @log = Hash.new { |hash, key| hash[key] = [] }
  end

  def allow?(key, now)
    stamps = prune(key, now)
    return false if stamps.size >= @limit
    stamps << now
    true
  end

  def remaining(key, now)
    @limit - prune(key, now).size
  end

  private

  # Accepted timestamps still inside the window, oldest first. Expired ones are dropped,
  # so each key holds at most `limit` entries regardless of traffic.
  def prune(key, now)
    stamps = @log[key]
    stamps.shift while !stamps.empty? && now - stamps.first >= @window
    stamps
  end
end
