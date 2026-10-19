# Backfill Legacy Customer Emails
A rolling deployment adds normalized_email to a legacy customer table. Implement the supplied Ruby service and update the read endpoint while old writers may still leave the new column NULL.

## Schema and API
Keep legacy email unchanged. Add nullable normalized_email if necessary and a UNIQUE database index on (organization_id, normalized_email). SQLite permits multiple NULLs. `GET /customers/:id` uses strict positive `X-Organization-ID`; invalid =>401, missing/foreign =>404. Return exactly id and email. Prefer a non-NULL normalized_email; otherwise return legacy email stripped and downcased (or null when legacy email is null). Never change persisted records on GET. Errors: `{ "errors": { "FIELD": ["MESSAGE"] } }`.

## CustomerEmailBackfill.call(after_id:, through_id:, batch_size:)
All arguments must be Ruby Integers: after_id >=0, through_id >= after_id, batch_size 1..100; otherwise raise ArgumentError. The caller captures through_id once as a high-water mark before a whole run. Select the next batch of ALL customer rows with id > after_id AND id <= through_id ordered by id, limited in SQL. Do not filter by migration state before selecting the batch.

Return a Hash with exactly :cursor, :scanned, :updated, :conflicts and :done. cursor is the last scanned ID (or after_id when none). scanned is rows selected. done means there are no further rows <= through_id after cursor, including exactly-full final batches. Existing non-NULL values stay untouched but still advance the cursor. Normalize legacy email with strip.downcase; null or whitespace-only remains NULL. Count updated only when a nonblank normalized value was written. If a same-tenant normalized address already exists, leave the row unchanged, increment conflicts and continue. Different tenants may share an address.

Use a database-guarded conditional write: only set normalized_email while it is still NULL AND legacy email is unchanged from the observed row. This prevents overwriting a newer dual-write or assigning a value from stale legacy data. Expected uniqueness conflicts may be handled; unexpected persistence errors must propagate. No network jobs or sleeps. This is a per-row resumable worker, not one giant transaction. A crash may commit earlier rows; retrying the previous cursor must be safe.

## Rollout discussion
Explain expand → dual-write → capture high-water mark → backfill → resolve conflicts → validate → switch reads → contract. Editing schema.rb in this exercise describes the final test schema, not a production migration runner. Discuss how to create the unique index safely with existing duplicates, old-writer reconciliation, PostgreSQL concurrent indexes, bounded locks and rollback.

Twelve test groups cover behavior, schema, bounded loading, retry, and deliberately interleaved writes; they do not certify an online migration in production.
