def merge_intervals(intervals)
  intervals.sort_by { |start, finish| [start, finish] }.each_with_object([]) do |(start, finish), merged|
    if merged.empty? || start > merged.last[1]
      merged << [start, finish]
    else
      merged.last[1] = [merged.last[1], finish].max
    end
  end
end
