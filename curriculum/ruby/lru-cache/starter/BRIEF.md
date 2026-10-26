# Bounded LRU Cache

Implement `LruCache` in solution.rb: a cache holding at most `capacity` entries that evicts the least recently used entry when a new key would exceed the capacity.

## Contract
- `LruCache.new(capacity)`: `capacity` is a positive Integer; anything else raises `ArgumentError`.
- `get(key)`: returns the stored value, or `nil` when absent, and marks the key as most recently used. A stored `nil` is a real entry: it occupies capacity, appears in `keys`, and reading it refreshes its recency, but `get` still returns `nil` for it. Callers cannot tell a stored `nil` from an absent key through `get`; that is the published contract, not a gap, and no sentinel or extra method is expected. Only your implementation must tell the two apart, so that a stored `nil` is kept, counted and refreshed, and a missing key inserts nothing.
- `put(key, value)`: inserts or replaces the value, marks the key as most recently used, then evicts the least recently used entry if the cache now holds more than `capacity` entries. Replacing an existing key never evicts.
- `size`: the number of stored entries.
- `keys`: every stored key from least recently used to most recently used.
- Keys may be any hashable Ruby object. `get` and `put` must take constant time on average; sequences of 100,000 operations are checked.

Example: with capacity 2, `put(:a, 1)`, `put(:b, 2)`, `get(:a)`, `put(:c, 3)` leaves `keys == [:a, :c]` and `get(:b)` returns `nil`.

## Your workspace
Only solution.rb is editable. Six visible test groups are provided under test/. Each run also checks six additional groups covering the same published contract: capacity one, `nil` values, non-trivial keys, generated operation sequences against an independent oracle, and 100,000-operation sequences. These are practice checks, not a tamper-resistant assessment grade.

Prepare checks syntax without running your implementation. Run tests executes the saved revision in the local Linux sandbox, with no network, a 60-second execution limit, and bounded memory/output.

## Thinking and handoff
30 minutes. Explain which structure gives constant-time lookup and constant-time reordering in Ruby, what "most recently used" means for a replaced key, and why the eviction check happens after insertion. Predict one sequence that would expose an off-by-one in eviction before running tests.

Follow-up: entries now also expire after a fixed time-to-live. Explain what changes in `get`, what the eviction rule becomes, and what you would measure. This extension is discussed separately; it is not required for the original contract.
