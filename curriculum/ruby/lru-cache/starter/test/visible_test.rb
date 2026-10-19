require "minitest/autorun"
require_relative "../solution"

class VisibleLruCacheTest < Minitest::Test
  def test_missing_key_returns_nil
    cache = LruCache.new(2)
    assert_nil cache.get(:absent)
    assert_equal 0, cache.size
  end
  def test_put_then_get_returns_the_value
    cache = LruCache.new(2)
    cache.put(:a, 1)
    assert_equal 1, cache.get(:a)
    assert_equal 1, cache.size
  end
  def test_least_recently_used_key_is_evicted_beyond_capacity
    cache = LruCache.new(2)
    cache.put(:a, 1)
    cache.put(:b, 2)
    cache.put(:c, 3)
    assert_nil cache.get(:a)
    assert_equal [:b, :c], cache.keys
  end
  def test_get_refreshes_recency
    cache = LruCache.new(2)
    cache.put(:a, 1)
    cache.put(:b, 2)
    cache.get(:a)
    cache.put(:c, 3)
    assert_nil cache.get(:b)
    assert_equal [:a, :c], cache.keys
  end
  def test_replacing_an_existing_key_refreshes_without_evicting
    cache = LruCache.new(2)
    cache.put(:a, 1)
    cache.put(:b, 2)
    cache.put(:a, 10)
    assert_equal 2, cache.size
    assert_equal [:b, :a], cache.keys
    assert_equal 10, cache.get(:a)
  end
  def test_capacity_must_be_a_positive_integer
    assert_raises(ArgumentError) { LruCache.new(0) }
    assert_raises(ArgumentError) { LruCache.new("3") }
  end
end
