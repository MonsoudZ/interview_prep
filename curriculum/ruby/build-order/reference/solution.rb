class CycleError < StandardError
end

# Kahn's algorithm with a binary min-heap of ready tasks, so each step takes the
# smallest ready task in logarithmic time. Costs O((tasks + dependencies) log tasks).
def build_order(tasks, dependencies)
  known = tasks.to_h { |task| [task, true] }
  waiting = Hash.new(0)
  followers = Hash.new { |hash, key| hash[key] = [] }
  seen = {}
  dependencies.each do |before, after|
    raise ArgumentError, "unknown task in dependency #{before.inspect} -> #{after.inspect}" unless known[before] && known[after]
    raise ArgumentError, "#{after.inspect} depends on itself" if before == after
    next if seen[[before, after]]
    seen[[before, after]] = true
    waiting[after] += 1
    followers[before] << after
  end
  heap = MinHeap.new
  tasks.each { |task| heap.push(task) if waiting[task].zero? }
  order = []
  until heap.empty?
    task = heap.pop
    order << task
    followers[task].each do |follower|
      waiting[follower] -= 1
      heap.push(follower) if waiting[follower].zero?
    end
  end
  raise CycleError, "#{tasks.size - order.size} tasks are part of a dependency cycle" if order.size < tasks.size
  order
end

class MinHeap
  def initialize
    @items = []
  end

  def empty?
    @items.empty?
  end

  def push(item)
    @items << item
    child = @items.size - 1
    while child.positive?
      parent = (child - 1) / 2
      break if @items[parent] <= @items[child]
      @items[parent], @items[child] = @items[child], @items[parent]
      child = parent
    end
  end

  def pop
    top = @items.first
    last = @items.pop
    unless @items.empty?
      @items[0] = last
      parent = 0
      loop do
        left = parent * 2 + 1
        right = left + 1
        smallest = parent
        smallest = left if left < @items.size && @items[left] < @items[smallest]
        smallest = right if right < @items.size && @items[right] < @items[smallest]
        break if smallest == parent
        @items[parent], @items[smallest] = @items[smallest], @items[parent]
        parent = smallest
      end
    end
    top
  end
end
