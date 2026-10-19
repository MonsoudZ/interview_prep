# Representative exercise contracts

These are design contracts for the full application. A representative Rails starter, reference implementation, and 12 executable test groups have now been validated in the [local runtime experiment](rails-runtime-experiment.md). The [published curriculum](../curriculum/README.md) now adds four further executable Rails repositories and executable Ruby intervals, with tested references, mutation checks, and actual Linux integration. Calibrated rubrics, design workspace implementation, and automated sample reviews remain to be produced.

## Shared evaluation contract

Each finding includes severity/category, artifact revision and location, evidence, consequence, recommended action, and confidence. Label verified defects, design concerns, and optional refinements separately.

Report independent performance separately from assisted learning. Use anchored rubric judgments rather than an unexplained aggregate score. Senior expectations must remain relevant to stated requirements and available time.

Each review includes a practice verdict with limitations, supported strengths, prioritized findings, reference alternatives, an understanding check, revision work, and fresh transfer practice.

## Rails: Repository Events API

### Setup

Minimal Rails repository; configured database and test framework; 12 visible tests. Suggested independent assessment: 50 minutes. Learning variants add examples and checklists.

### Proposed exact behavior

Event fields: generated integer `id`, `event_type`, positive integer `actor_id`, positive integer `repository_id`, and `occurred_at`.

Allowed types: `push`, `pull_request`, `issue`. Timestamp input is an ISO 8601 string with an explicit offset. Serialize UTC timestamps with millisecond precision. Successful event objects contain exactly these five fields.

POST accepts a JSON object under `event`. Ignore unknown attributes; never accept a client-supplied ID. Missing/malformed event fields are validation failures. Syntactically malformed JSON returns 400. JSON responses use the appropriate JSON content type.

| Request | Result |
| --- | --- |
| POST /events | 201 with event; persist exactly one valid record |
| GET /events | 200 with array ordered by ascending ID; empty array if none |
| GET /events/:id | 200 with event; 404 if no matching integer ID |
| GET /events?repository_id=7 | 200 with matching records in ascending ID order |
| Invalid POST fields | 422; persist nothing |
| Invalid repository filter | 400 |

Integer IDs and filters accept positive decimal integers only. An unknown positive repository filter returns an empty array. This exercise does not model repository or actor tables. No authentication, update/delete endpoints, pagination, or concurrency implementation is required.

Error shape: `{ "errors": { "field": ["message"] } }`; non-field errors use `base`. Field names and non-empty message arrays are contractual; exact wording is not. Missing resources use the same envelope with a base message.

### Twelve visible test groups

1. Valid creation, status, response fields, persisted record.
2. Missing required fields and no persistence.
3. Unsupported event type.
4. Invalid identifiers.
5. Invalid timestamp.
6. Empty listing.
7. Ascending listing.
8. Existing-event lookup.
9. Missing/invalid-ID lookup.
10. Matching repository filter.
11. Nonmatching repository filter.
12. Invalid filter, unknown attributes, and protected generated ID behavior.

Additional grading checks exercise only published behavior. Test groups may contain multiple assertions/cases. Final test count and framework are to be fixed in the executable exercise version.

### Review and follow-up

Prioritize correctness, HTTP behavior, idiomatic Rails, validation, and readable implementation. Do not require service objects. Discuss database constraints as a follow-up; do not retroactively require them for an unstated concurrency guarantee.

Example finding: controller renders 201 after `save` returns false. Demonstrate an invalid request, cite the relevant branch, explain the false success signal, and recommend returning the contractual validation response.

## Ruby: Merge Busy Intervals

### Contract

Implement `merge_intervals(intervals)`. Input contains zero or more two-integer arrays `[start, finish]`, with `start <= finish`. Inputs are valid and may be unsorted. Negative values and zero-duration intervals are allowed. Touching intervals merge. Return disjoint merged intervals in ascending start order. Do not mutate input arrays. Assessment: approximately 35 minutes.

Example: `[[5, 7], [1, 3], [3, 4], [9, 12]]` returns `[[1, 4], [5, 7], [9, 12]]`.

Constraints for the executable version: up to 100,000 intervals, integer endpoints in [-1,000,000,000, 1,000,000,000]. No external packages needed.

### Interview and evidence

Allow examples/code as thinking tools. Ask for approach, correctness, complexity, edge cases, and tests. Expect a suitable sorting-and-scan approach without demanding one specific implementation. Review empty input, nesting, duplicates, boundaries, and mutation.

Follow-up: input arrives already sorted. Record it as an extension with separate assessment.

Example finding: nested intervals shrink the result when the accumulated endpoint is overwritten. Counterexample `[[1, 10], [2, 3]]`; expected `[[1, 10]]`. Preserve the maximum endpoint.

A correct explanation with input mutation receives separate reasoning credit and an implementation defect; do not collapse the distinction.

## System design: Reliable Webhook Delivery

### Opening prompt

Design a service delivering repository events to customer-configured HTTPS endpoints. Customers subscribe endpoints and inspect delivery outcomes. Assessment: approximately 50 minutes.

### Proposed interviewer fact sheet

- 10,000 customer endpoints; 1,000 incoming events/second normally, 10,000 at peak.
- Average payload 2 KB; average fan-out three subscribed endpoints per event.
- Healthy-endpoint goal: 95% of first delivery attempts start within 10 seconds of acceptance.
- Accepted events must survive a single process or machine failure.
- At-least-once delivery attempts; duplicates are possible and customers need stable identifiers.
- No global ordering requirement. Discuss per-repository ordering only if introduced as an extension.
- Retry transient failures for up to 24 hours with a bounded policy. Clearly define success and permanent-failure behavior.
- Retain delivery metadata for 30 days; payload retention and sensitive-data handling are explicit design decisions.
- Customers can inspect status and request replay; authorization and replay semantics must be explained.
- Single-region initial deployment; multi-region is an optional follow-up.

Publish clarified requirements in session notes. If the interviewer supplies an unasked critical requirement, record the prompt. These figures are fictional exercise assumptions, not provider capabilities.

### Evaluation

Assess requirements, API/data model, durable acceptance boundary, dispatch/retry design, duplicates, fairness, destination security, request signing, observability, and operational judgment. Depth should follow the stated scale/time. No particular messaging product is mandatory.

Scenario: a large customer's endpoint fails for two hours. Probe backpressure, isolation, retry growth, recovery, and inspection. Credit reasoned revisions and record prompting.

Example finding: acknowledgment precedes durable storage/queue acceptance, so a process crash loses an accepted event. Cite the ingestion sequence and require a defined durable boundary and retry behavior.

Accept a justified database-backed queue if the design explains throughput, contention, worker claiming, durability, and recovery sufficiently for the stated requirements.

## Required validation before scored use

- Rails: implement and execute starter/reference repositories and all contract cases; confirm readiness and time calibration.
- Ruby: execute reference and intentionally flawed solutions against boundary, mutation, and larger-input cases.
- Design: prepare human-reviewed example answers at multiple levels and valid architectural alternatives.
- All tracks: verify reviewers cite evidence, avoid invented requirements, distinguish help from independence, and preserve original submissions during revision.
