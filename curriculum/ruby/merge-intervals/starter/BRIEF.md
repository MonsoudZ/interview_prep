# Merge Busy Intervals

Implement `merge_intervals(intervals)` in solution.rb. Return intervals covering exactly the input, merged into ascending, disjoint intervals. Overlapping OR touching intervals merge. Inputs are valid, may be unsorted, and must not be mutated (including nested arrays).

Input: zero to 100,000 two-integer arrays `[start, finish]`, with start <= finish. Endpoints range from -1,000,000,000 to 1,000,000,000. Negative values, duplicates, nesting, and zero-length intervals are allowed. Return an array of two-integer arrays. No external packages are needed.

Example: `[[5,7],[1,3],[3,4],[9,12]]` → `[[1,4],[5,7],[9,12]]`.

## Your workspace
Only solution.rb is editable. Six visible test groups are provided under test/. Each run also checks six additional groups covering the same published contract: boundaries, input ownership, generated cases, and 100,000-interval inputs. Additional fixtures are not in the editor; their failure messages identify the contract category without exposing full fixtures. These are practice checks, not a tamper-resistant assessment grade.

Prepare checks syntax without running your implementation. Run tests executes the saved revision in the local Linux sandbox, with no network, a 60-second execution limit, and bounded memory/output. A timeout is an execution outcome, not a calibrated complexity score. The same revision is attached to the result and eventual submission.

## Thinking and handoff
35 minutes. Explain your approach, the invariant after each iteration, why nested intervals cannot shrink the result, and the time and space costs. Predict a counterexample before running tests. Keep correctness, Ruby ownership behavior, and complexity separate in your explanation.

Follow-up: the input now arrives already sorted. Explain what can be emitted incrementally. This extension is discussed separately; it is not required for the original batch function.
