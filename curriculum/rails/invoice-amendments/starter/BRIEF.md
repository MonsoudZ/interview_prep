# Prevent Lost Invoice Updates
Two browser tabs overwrite invoice totals. Extend the supplied endpoint with compare-and-swap revisions while preserving its JSON contract.

`PATCH /invoices/:id` uses trusted gateway `X-Organization-ID` (positive decimal; missing/malformed => 401). Scope lookup to that organization; missing/foreign => 404. Body `{ "invoice": { "amount_cents": INTEGER, "expected_version": INTEGER } }`. Both must be JSON integers; amount 1..100000000, version >=0. Bad envelopes/values => 422. Unknown fields are ignored. Only draft invoices may change; paid =>409.

Success returns exactly `{ "id": ID, "amount_cents": AMOUNT, "version": OLD_VERSION+1 }` with 200. Accept only if expected_version equals the persisted version. A stale write (including replay of a successful request) returns 409 and changes nothing. Increment even if the amount is unchanged. Never trust a client-supplied organization, status, or next version.

Persist exactly one InvoiceAmendment with invoice_id, version (the new version), old_amount_cents and new_amount_cents. The invoice mutation and amendment insertion must be atomic. Unexpected persistence errors propagate, leaving the old invoice unchanged.

## Database guarantees
Enforce uniqueness of (invoice_id, version) and a positive amount_cents with a database constraint; model validation alone is insufficient. Guard the update with the expected version in the database predicate (or an equivalent locking strategy) so two requests cannot both claim the same revision. Tests cover stale writes, schema constraints and rollback. Passing sequential tests is not a production concurrency benchmark; explain the SQL and behavior under your target database's isolation level.

Error shape: `{ "errors": { "FIELD": ["MESSAGE"] } }`. Test file includes 12 groups. Discuss 409 versus HTTP If-Match/412, client conflict resolution, database retry policy, and how to migrate existing API clients.
