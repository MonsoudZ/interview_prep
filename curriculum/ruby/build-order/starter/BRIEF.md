# Deterministic Build Order

Implement `build_order(tasks, dependencies)` in solution.rb.

## Contract
- `tasks`: an Array of unique String names. `dependencies`: an Array of `[before, after]` pairs meaning `before` must appear earlier than `after`.
- Return an Array containing every task exactly once in an order that satisfies every dependency.
- Determinism: whenever more than one task is ready (all of its dependencies already placed), place the smallest String first. Two correct implementations must therefore return identical arrays.
- Raise `ArgumentError` when a dependency names a task that is not in `tasks`, or when a task depends on itself.
- Raise `CycleError` (defined in solution.rb) when the dependencies contain a cycle.
- Do not mutate `tasks` or `dependencies`. Duplicate dependency pairs are allowed and mean the same thing once.
- Inputs reach 100,000 tasks and 200,000 dependencies; the ready set can itself hold 100,000 tasks, so choosing the smallest ready task must not scan the whole set each time.

Example: tasks `["lint", "test", "build", "deploy"]`, dependencies `[["build", "test"], ["build", "deploy"], ["test", "deploy"]]` gives `["build", "lint", "test", "deploy"]`: `build` and `lint` are ready first and `build` is smaller.

## Your workspace
Only solution.rb is editable. Six visible test groups are provided under test/. Each run also checks six additional groups covering the same published contract: self-dependencies, duplicate pairs, generated graphs verified step by step, a 100,000-task chain, 100,000 independent tasks, and a 100,000-task cycle. These are practice checks, not a tamper-resistant assessment grade.

Prepare checks syntax without running your implementation. Run tests executes the saved revision in the local Linux sandbox, with no network, a 60-second execution limit, and bounded memory/output.

## Thinking and handoff
40 minutes. Explain how you track how many dependencies each task still waits on, how you find the smallest ready task without a linear scan, how a cycle shows up at the end, and the cost in terms of tasks and dependencies. Predict which visible test a plain depth-first search would fail.

Follow-up: tasks now have durations and may run on two workers in parallel. Explain what the ordering no longer decides, what you would compute instead, and where determinism still matters. This extension is discussed separately; it is not required for the original contract.
