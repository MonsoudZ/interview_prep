# Trusted supplemental practice checks. Fixtures are omitted from the editor, not secret from sandbox code.
require "minitest/autorun"
class AdditionalBuildOrderTest < Minitest::Test
  def test_self_dependency_is_an_argument_error
    assert_raises(ArgumentError, "A task depending on itself is invalid input, not a cycle") { build_order(%w[a b], [%w[a a]]) }
  end
  def test_duplicate_dependency_pairs_mean_the_same_thing_once
    assert build_order(%w[b a], [%w[a b], %w[a b], %w[a b]]) == %w[a b], "Duplicate pairs must not block a task"
  end
  def test_generated_graphs_place_the_smallest_ready_task_at_every_step
    random = Random.new(2718)
    30.times do
      count = random.rand(1..40)
      tasks = (0...count).map { |i| format("t%03d", i) }.shuffle(random: random)
      ranks = tasks.each_with_index.to_h
      dependencies = Array.new(random.rand(0..80)) do
        a, b = tasks.sample(2, random: random)
        a == b ? nil : (ranks[a] < ranks[b] ? [a, b] : [b, a])
      end.compact
      order = build_order(tasks, dependencies)
      assert order.sort == tasks.sort, "Every task must appear exactly once"
      position = order.each_with_index.to_h
      dependencies.each { |before, after| assert position[before] < position[after], "Dependency #{before} -> #{after} violated" }
      waiting = Hash.new { |h, k| h[k] = [] }
      dependencies.each { |before, after| waiting[after] << before }
      placed = {}
      order.each do |task|
        ready = tasks.reject { |t| placed[t] }.select { |t| waiting[t].all? { |before| placed[before] } }
        assert task == ready.min, "Expected the smallest ready task #{ready.min}, got #{task}"
        placed[task] = true
      end
    end
  end
  def test_one_hundred_thousand_task_chain
    tasks = (0...100_000).map { |i| format("n%06d", i) }
    dependencies = tasks.each_cons(2).to_a.reverse
    assert build_order(tasks.reverse, dependencies) == tasks, "Long chain contract failed"
  end
  def test_one_hundred_thousand_independent_tasks_come_out_sorted_in_bounded_time
    tasks = (0...100_000).map { |i| format("n%06d", i) }.shuffle(random: Random.new(7))
    assert build_order(tasks, []) == tasks.sort, "Choosing the smallest ready task must not scan the whole ready set each step"
  end
  def test_one_hundred_thousand_task_cycle_is_detected
    tasks = (0...100_000).map { |i| format("n%06d", i) }
    dependencies = tasks.each_cons(2).to_a + [[tasks.last, tasks.first]]
    assert_raises(CycleError, "A cycle through every task must raise") { build_order(tasks, dependencies) }
  end
end
