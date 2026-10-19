# Sliding-Window Rate Limiter

Implement `RateLimiter` in solution.rb: at most `limit` requests per key within any sliding window of `window_seconds`.

## Contract
- `RateLimiter.new(limit:, window_seconds:)`: `limit` is a positive Integer and `window_seconds` a positive Numeric; anything else raises `ArgumentError`.
- `allow?(key, now)`: `now` is a Numeric timestamp in seconds supplied by the caller; it never decreases for a given key. A recorded request at time `t` still counts while `now - t < window_seconds` and has expired once `now - t >= window_seconds`. If fewer than `limit` requests still count, record this request at `now` and return `true`; otherwise return `false` and record nothing.
- `remaining(key, now)`: how many more requests would be allowed at `now` without recording anything.
- Keys are independent and may be any hashable object. Several requests may share the same `now`.
- Memory must not grow with rejected requests or with expired requests; sequences of 100,000 calls on one key are checked.

Example: `limit: 2, window_seconds: 10`; `allow?(:k, 0)` and `allow?(:k, 5)` return `true`, `allow?(:k, 9.9)` returns `false`, `allow?(:k, 10)` returns `true` because the request at `0` has expired.

## Your workspace
Only solution.rb is editable. Six visible test groups are provided under test/. Each run also checks six additional groups covering the same published contract: exact boundaries, rejected requests, equal timestamps, generated sequences against an independent oracle, and 100,000-call sequences. These are practice checks, not a tamper-resistant assessment grade.

Prepare checks syntax without running your implementation. Run tests executes the saved revision in the local Linux sandbox, with no network, a 60-second execution limit, and bounded memory/output.

## Thinking and handoff
35 minutes. Explain the difference between a fixed window and a sliding window, where the boundary falls and why, why a rejected request must not be recorded, and how you keep memory bounded. Say what the cost per call is in terms of `limit`.

Follow-up: the limiter now runs on several application servers at once. Explain what breaks, what the shared state would be, and what you would accept being approximate. This extension is discussed separately; it is not required for the original contract.
