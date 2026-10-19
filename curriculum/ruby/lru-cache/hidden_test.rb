# Trusted supplemental practice checks. Fixtures are omitted from the editor, not secret from sandbox code.
require "minitest/autorun"
class AdditionalLruCacheTest < Minitest::Test
  def test_capacity_one_keeps_only_the_latest_key
    cache = LruCache.new(1)
    cache.put(:a, 1)
    cache.put(:b, 2)
    assert cache.get(:a).nil? && cache.get(:b) == 2 && cache.keys == [:b], "Capacity-one contract failed"
  end
  def test_nil_values_are_stored_and_count_toward_capacity
    cache = LruCache.new(2)
    cache.put(:a, nil)
    cache.put(:b, 2)
    cache.put(:c, 3)
    assert cache.size == 2 && cache.keys == [:b, :c], "nil values must occupy a slot"
  end
  def test_keys_of_any_hashable_type
    cache = LruCache.new(3)
    cache.put([1, 2], "array")
    cache.put("s", "string")
    cache.put(7, "integer")
    assert cache.get([1, 2]) == "array" && cache.keys == ["s", 7, [1, 2]], "Hashable key contract failed"
  end
  def test_generated_operations_match_an_independent_oracle
    random = Random.new(90417)
    50.times do
      capacity = random.rand(1..6)
      cache = LruCache.new(capacity)
      oracle = [] # [key, value] pairs, least recently used first
      300.times do
        key = random.rand(1..9)
        if random.rand < 0.4
          entry = oracle.find { |k, _| k == key }
          if entry
            oracle.delete(entry)
            oracle << entry
          end
          assert cache.get(key) == entry&.last, "Generated get diverged from the oracle"
        else
          value = random.rand(1000)
          oracle.delete_if { |k, _| k == key }
          oracle << [key, value]
          oracle.shift if oracle.size > capacity
          cache.put(key, value)
        end
        assert cache.keys == oracle.map(&:first) && cache.size == oracle.size, "Generated order diverged from the oracle"
      end
    end
  end
  def test_one_hundred_thousand_puts_stay_within_capacity
    cache = LruCache.new(1000)
    100_000.times { |i| cache.put(i, i) }
    assert cache.size == 1000 && cache.keys.first == 99_000 && cache.get(98_999).nil?, "Large put sequence contract failed"
  end
  def test_one_hundred_thousand_reads_refresh_in_bounded_time
    cache = LruCache.new(50_000)
    50_000.times { |i| cache.put(i, i) }
    100_000.times { |i| cache.get(i % 50_000) }
    cache.put(:newest, true)
    assert cache.keys.first == 1 && cache.keys.last == :newest, "Reads must refresh recency in bounded time"
  end
end
