# Repair Support Escalations
A deployed support tool has leaked tickets and recorded misleading audits. Repair the existing Rails endpoint without changing its contract.

## Gateway identity
The test gateway supplies `X-Agent-ID`, a positive decimal ID of an existing Agent. Missing, malformed or unknown agents return 401. This is a trusted test gateway, not production authentication. Never use request body fields as identity.

## POST /tickets/:id/escalate
Find the ticket inside the agent's organization; unknown and foreign tickets return 404 before checking role. Only `supervisor` agents can escalate; all other roles return 403. The ticket must be `open`; `escalated` or `closed` returns 409 with no writes. Body is `{ "escalation": { "reason": "..." } }`; trim whitespace, accept 10–200 characters, reject missing/non-object/non-string input with 422. Unknown attributes are ignored.

Success returns 200 with exactly `{ "id": INTEGER, "status": "escalated", "reason": STRING }`. Persist the trimmed reason and exactly one EscalationAudit with ticket_id, agent_id and reason. Ticket change and audit are one atomic operation. A duplicate call returns 409, not another audit. Unexpected persistence errors propagate and roll back both changes; do not turn storage failures into success or validation errors.

Errors use `{ "errors": { "FIELD": ["MESSAGE"] } }`. Keep unrelated ticket data unchanged. Existing models and a deliberately flawed controller are supplied; use the 12 tests to investigate, repair, and explain the underlying defects.

## Discussion
Explain the trust boundary, why 404 precedes 403, transaction scope, and what additional protection simultaneous escalations require on PostgreSQL. These tests verify sequential behavior and rollback, not production concurrency.
