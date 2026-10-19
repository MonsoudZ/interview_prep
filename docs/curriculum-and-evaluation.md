# Curriculum and evaluation framework

Status: planning inventory and proposed rubric. Exercise content and scoring are not validated yet.

## Progression

Each skill supports worked explanation, analogous practice, checklist practice, independent work, and timed application. Not every exercise needs five duplicate implementations. Scaffold variants must fade support; fresh tasks test transfer.

Start the user with examples for Rails. Algorithms and system design baselines remain unknown until optional diagnostics or ordinary practice provide evidence. Do not infer inability in those tracks from Rails recall difficulties.

## Proposed inventory: 24 Rails packages

| Group | Six package topics |
| --- | --- |
| Foundations | Request flow; JSON listing; record lookup; create endpoint; validation/errors; update/delete |
| Data access | Associations; filtering/sorting; pagination; uniqueness constraints; transactions; query/N+1 diagnosis |
| Reliability | Concurrent updates; idempotent creation; background jobs; retries/timeouts; external API fixture; authorization boundaries |
| Integrated work | Events API; ticket workflow; order state transitions; broken API investigation; behavior-preserving refactor; production-style failure diagnosis |

Foundation exercises are not all senior assessments. Integrated exercises apply a senior rubric appropriate to their scope.

## Proposed inventory: 24 Ruby packages

| Group | Six package topics |
| --- | --- |
| Core patterns | Frequency maps; two pointers; sliding window; prefix sums; intervals; binary search |
| Structures | Stack parsing; queue traversal; linked-list operations; tree traversal; BST reasoning; heap/top-k |
| Search | Graph BFS; graph DFS; cycle detection; topological ordering; backtracking; recursion/memoization |
| Applied combinations | One-dimensional DP; grid DP; dependency scheduling; streaming aggregation; LRU cache; constraint-changing mixed interview |

Each package includes edge cases, complexity discussion, Ruby-specific considerations, and follow-ups. Difficulty progression within packages prevents starting with arbitrary hard problems.

## Proposed inventory: 12 design packages

Components: rate limiting, caching/invalidation, reliable job processing, pagination/data access, idempotency/concurrency, observability/recovery.

Complete designs: webhook delivery, notification platform, file upload/storage, activity feed, reservation/scheduling, event ingestion/querying.

Each includes a fact sheet, requirement-discovery prompts, tradeoff branches, failure scenario, reference alternatives, and anchored sample responses. Difficulties and scales vary by mode.

## Anchored ratings

| Rating | Meaning |
| --- | --- |
| Not observed | Session did not provide enough evidence; excluded from verdict aggregation |
| Needs development | Cannot yet handle the relevant requirement without substantial help, or leaves a material unresolved defect |
| Approaching target | Handles the main path but needs prompting for important cases or tradeoffs |
| Meets target | Independently delivers/explains an appropriate solution and relevant boundaries |
| Exceeds target | Demonstrates additional relevant depth and judgment without unnecessary complexity |

Evaluate only applicable dimensions. Report correctness, reasoning, judgment, implementation, reliability, communication, and independence separately. Assistance is contextual evidence, not an automatic score deduction across every category.

No universal numerical average. Proposed verdicts: strong pass, pass, borderline, below target, insufficient evidence. Exercise-specific anchors define critical requirements; an unresolved critical correctness/reliability defect prevents a pass for that requirement. Do not invent a universal hiring cutoff from these labels.

## Calibrating reviews

For each scored exercise, prepare human-reviewed examples: strong, acceptable, partial, flawed, and valid alternative. Include unsupported-criticism traps, prompt-injection text, and assistance variations.

Measure critical-defect detection, unsupported findings, evidence-reference correctness, alternative acceptance, consistency across repeat evaluations, and separation of assisted/independent outcomes. Set numerical release thresholds after a baseline review study; do not claim unmeasured accuracy.

Minimum release gate: known critical defects in the maintained regression set are detected; every surfaced finding resolves to evidence; no known valid alternative in that set is rejected solely for stylistic preference. Document limitations and residual disagreements.

## Recommendations

Initial recommendations use transparent rules, not opaque personalization: unresolved material skill gaps first; then fresh transfer exercises; then spaced revisits; then time-pressure practice. Display supporting observations and allow override.

One completion does not establish mastery. Retakes of the same problem are labeled as such. Track assisted completion, fresh independent completion, timed completion, and later retention checks independently. Do not interpret inactivity as declining technical ability.
