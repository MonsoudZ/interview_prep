# Trusted supplemental practice checks. Fixtures are omitted from the editor, not secret from sandbox code.
require "minitest/autorun"
class AdditionalIntervalsTest < Minitest::Test
  def test_endpoint_boundaries_and_duplicates
    input = [[1_000_000_000, 1_000_000_000], [-1_000_000_000, -1_000_000_000], [-1_000_000_000, -1_000_000_000]]
    assert merge_intervals(input) == [[-1_000_000_000, -1_000_000_000], [1_000_000_000, 1_000_000_000]], "Boundary/duplicate contract failed"
  end
  def test_input_and_nested_arrays_are_not_mutated
    input = [[8, 9], [1, 10], [2, 4]]
    before = Marshal.load(Marshal.dump(input))
    merge_intervals(input)
    assert input == before, "Input ownership contract failed"
    frozen_input = input.map(&:freeze).freeze
    assert merge_intervals(frozen_input) == [[1, 10]], "Frozen valid input must work without mutation"
  end
  def test_generated_cases_match_independent_coverage_oracle
    random = Random.new(41073)
    100.times do
      input = Array.new(random.rand(0..60)) { [random.rand(-25..25), random.rand(-25..25)].sort }
      # Sweep endpoint deltas, independently of a sorted-interval merging implementation.
      starts = Hash.new(0); finishes = Hash.new(0)
      input.each { |a, b| starts[a] += 1; finishes[b] += 1 }
      active = 0; opening = nil; expected = []
      (starts.keys | finishes.keys).sort.each do |point|
        opening = point if active == 0
        active += starts[point]
        active -= finishes[point]
        expected << [opening, point] if active == 0
      end
      assert merge_intervals(input) == expected, "Generated valid-input coverage contract failed"
    end
  end
  def test_one_hundred_thousand_disjoint_intervals
    expected = Array.new(100_000) { |i| [i * 3, i * 3 + 1] }
    assert merge_intervals(expected.reverse) == expected, "100,000 disjoint intervals must remain sorted and separate"
  end
  def test_one_hundred_thousand_nested_intervals
    input = Array.new(100_000) { |i| [i, 200_000 - i] }
    assert merge_intervals(input.reverse) == [[0, 200_000]], "100,000 nested intervals must retain the farthest endpoint"
  end
  def test_one_hundred_thousand_shuffled_touching_intervals
    input = Array.new(100_000) { |i| [i, i + 1] }.shuffle(random: Random.new(82))
    assert merge_intervals(input) == [[0, 100_000]], "100,000 touching intervals must form one interval"
  end
end
