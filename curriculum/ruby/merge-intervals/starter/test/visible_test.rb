require "minitest/autorun"
require_relative "../solution"

class VisibleIntervalsTest < Minitest::Test
  def test_empty_input
    assert_equal [], merge_intervals([])
  end
  def test_unsorted_disjoint_intervals
    assert_equal [[1, 2], [5, 7], [9, 12]], merge_intervals([[9, 12], [1, 2], [5, 7]])
  end
  def test_overlap_chains
    assert_equal [[1, 9]], merge_intervals([[6, 9], [1, 4], [3, 7]])
  end
  def test_touching_endpoints_merge
    assert_equal [[1, 4], [5, 7], [9, 12]], merge_intervals([[5, 7], [1, 3], [3, 4], [9, 12]])
  end
  def test_nested_intervals_do_not_shrink
    assert_equal [[1, 10]], merge_intervals([[1, 10], [2, 3], [5, 7]])
  end
  def test_negative_and_zero_length_intervals
    assert_equal [[-5, 0], [2, 2]], merge_intervals([[0, 0], [-5, -2], [-2, 0], [2, 2]])
  end
end
