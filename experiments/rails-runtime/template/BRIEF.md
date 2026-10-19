# Repository Events API

Implement the provided routes in this Rails API. Schema and tests are ready.

An event has exactly `id`, `event_type`, `actor_id`, `repository_id`, `occurred_at` in its JSON representation. Types: `push`, `pull_request`, `issue`. Both foreign identifiers must be positive integers. No associated tables are required. `occurred_at` must be an ISO 8601 timestamp with explicit timezone; serialize UTC with three fractional digits.

- POST /events: body `{ "event": { ...fields... } }`; return 201 and saved event. Ignore unknown attributes and client-supplied ID.
- GET /events: return 200 and an array ordered by ascending ID.
- GET /events/:id: return 200 and an event, or 404 for absent/invalid ID.
- GET /events?repository_id=7: filter by positive decimal ID; return 400 for invalid filter, or an empty array for no match.
- Invalid/missing creation fields or malformed event envelope: return 422 and persist nothing. Malformed JSON: 400.

Errors use `{ "errors": { "field": ["message"] } }`; general errors use `base`. Exact messages are not prescribed. IDs in paths/filter strings must contain decimal digits only and be greater than zero. JSON number fields accept integers only, not strings, booleans, or fractional values.

Run `bundle exec ruby -Itest test/integration/events_test.rb` from the exercise directory. The experiment runner prepares the test database before this command. The starter intentionally has 12 failing tests. No authentication, pagination, or update/delete functionality is required.
