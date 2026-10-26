class LruCache
  def initialize(capacity)
    raise ArgumentError, "capacity must be a positive integer" unless capacity.is_a?(Integer) && capacity >= 1
    @capacity = capacity
    @entries = {}
  end

  def get(key)
    return nil unless @entries.key?(key)
    value = @entries.delete(key)
    @entries[key] = value
  end

  def put(key, value)
    @entries.delete(key)
    @entries[key] = value
    @entries.shift if @entries.size > @capacity
    value
  end

  def size
    @entries.size
  end

  def keys
    @entries.keys
  end
end
