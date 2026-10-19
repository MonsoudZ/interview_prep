# Repair a Slow Activity Feed

The existing GET /feed implementation passes a smoke test but becomes slow as data grows. Fix its correctness and performance without changing the JSON contract. Work from the existing models, controller, and visible tests.

## Contract
X-Organization-ID is a fictional trusted-gateway positive decimal integer; missing/malformed identity returns 401. Do not use query parameters as identity. No real authentication implementation is required.

GET /feed returns `{ "items": [...], "next_cursor": integer-or-null }`. Each item has exactly id, body, author_name, comments_count. Include only that organization's posts, in descending id order. Posts always have an author. Comments count includes every comment on that post; posts without comments have zero. Other organizations never affect results.

Optional limit defaults to 10; accept decimal integers 1–50. Optional before is a positive decimal post ID and selects id < before. Reject malformed/zero/negative values with 400 (including empty parameters and suffixes like 2oops). A valid cursor need not refer to an existing post. If more records remain, next_cursor is the last returned ID; otherwise null, including an empty page. No duplicate/skipped items while traversing a stable dataset. We do not require snapshot isolation for newly inserted/deleted posts.

## Measurable performance requirements
A request must perform at most FOUR SELECT statements involving posts/authors/comments, independent of page size and comment count. Filter and limit in SQL; do not load all posts or instantiate individual Comment records just to count them. The large-fixture test allows at most 110 instantiated records for a page of 50 from 200 posts. Counts/author data must still be correct. Setup queries and schema queries are excluded; response rendering queries are included. Tests inspect query/record counts, not machine-dependent timing.

The schema is editable if useful; an index is a discussion point, not a substitute for bounded loading. The supplied controller intentionally has both a tenant leak and an N+1 pattern.

All failures return JSON `{ "errors": { "base": ["message"] } }` with nonempty arrays. Wording is flexible.

## Time and handoff
60 minutes. Reproduce the query growth; define pagination boundaries; optimize while checking exact response values. Explain query count versus query cost, useful indexes, and how you would investigate production latency.

## Out of scope
No search engine, Redis, denormalized counter maintenance, timeline fan-out, real identity management, or benchmark service. Do not change the published contract to make the benchmark easier.
