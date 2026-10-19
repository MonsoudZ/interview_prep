require "minitest/autorun"
require_relative "../solution"

class VisibleBuildOrderTest < Minitest::Test
  def test_linear_chain
    assert_equal %w[fetch compile link], build_order(%w[link compile fetch], [%w[fetch compile], %w[compile link]])
  end
  def test_independent_tasks_come_out_sorted
    assert_equal %w[a b c], build_order(%w[c a b], [])
  end
  def test_smallest_ready_task_goes_first
    order = build_order(%w[lint test build deploy], [%w[build test], %w[build deploy], %w[test deploy]])
    assert_equal %w[build lint test deploy], order
  end
  def test_cycle_raises_cycle_error
    assert_raises(CycleError) { build_order(%w[a b c], [%w[a b], %w[b c], %w[c a]]) }
  end
  def test_unknown_task_in_a_dependency_raises_argument_error
    assert_raises(ArgumentError) { build_order(%w[a b], [%w[a zzz]]) }
  end
  def test_inputs_are_not_mutated
    tasks = %w[c b a]
    dependencies = [%w[c a], %w[b a]]
    before = Marshal.load(Marshal.dump([tasks, dependencies]))
    build_order(tasks, dependencies)
    assert_equal before, [tasks, dependencies]
  end
end
