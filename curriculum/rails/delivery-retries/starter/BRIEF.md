# Retry-Safe Delivery Job

A queue can deliver the same job more than once, and customer endpoints fail. Finish DeliveryJob in this existing Rails repository. A test transport is supplied; do not make real network calls.

## Entry point and data
Implement `DeliveryJob.perform_now(delivery_id)` using ActiveJob (already installed). DeliveryTransport.deliver(delivery) returns an integer HTTP status or raises DeliveryTransport::Unavailable. Its stub raises unless the visible test installs a response. Never rescue arbitrary programming/database failures.

Delivery has payload, status (pending/delivered/failed), attempts (initially 0), last_http_status (nullable), and last_error (nullable). A missing delivery is a no-op. A terminal delivered or failed delivery is also a no-op; do not call transport or change counters again.

Each actual transport call increments attempts once, including Unavailable exceptions. A 2xx result marks delivered and clears last_error. A 4xx other than 429 marks failed permanently. A 3xx or 5xx, a 429, or Unavailable is transient: keep pending and raise DeliveryJob::Retryable while attempts < 3; on the third attempt mark failed and return normally. Retryable must be raised after the attempt state is durable, so an enclosing rollback does not erase it.

Persist last_http_status for HTTP responses, and nil for Unavailable. last_error must be nil on success and a nonempty string on transient or permanent failure. Preserve payload throughout. No automatic retry scheduling is required: tests simulate queue retries by invoking perform_now again. A real queue scheduler/backoff is a follow-up. A Retryable exception is the signal to that scheduler.

Use the delivery's own state to suppress sequential duplicate jobs. Missing records and terminal jobs never call the transport. The tests verify sequential retries, not simultaneous worker claiming or exactly-once remote effects. Explain why a crash after remote acceptance but before the local commit can still duplicate delivery.

## Time and handoff
60 minutes. Write a transition table before implementing the branches. Explain which state is committed before raising, what exception classes you intentionally catch, and which safety properties need a downstream idempotency key.

## Out of scope
No real HTTP, secrets, queue server, automatic backoff, distributed locks, or exactly-once claim. Model the published behavior precisely before discussing those extensions.
