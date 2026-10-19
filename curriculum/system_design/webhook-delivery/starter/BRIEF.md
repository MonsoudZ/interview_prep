# Reliable Webhook Delivery

Design a service delivering repository events to customer-configured HTTPS endpoints. Customers configure subscriptions, inspect delivery outcomes, and request replay. Use the architecture canvas and notes to explain a coherent design; no particular vendor or messaging product is required.

## Published assumptions

- 10,000 customer endpoints; 1,000 incoming events/second normally and 10,000 at peak.
- Average event payload: 2 KB. Average fan-out: three subscribed endpoints per event.
- For healthy endpoints, 95% of first delivery attempts should start within 10 seconds of acceptance.
- An accepted event survives a single process or machine failure.
- At-least-once delivery attempts: duplicates are possible. No global ordering requirement.
- Retry transient failures for up to 24 hours with a bounded policy. Define success and permanent-failure behavior.
- Retain delivery metadata for 30 days. Payload retention and sensitive-data handling are explicit choices.
- Start in one region. Multi-region and ordered per-repository delivery are extensions.

These are fictional interview assumptions. State further assumptions in Requirements rather than treating them as undisclosed requirements.

## Your workspace

Add components, name their responsibilities, and label connections with data or operations. Components can represent clients, services, databases, queues, caches, or external systems. Drag or use arrow keys to move a selected component; Shift moves farther. Select components/connections to edit them. Undo/redo applies to architecture changes; each notes section has its own editor history. Drag blank canvas space to pan. Fit and zoom affect only the view.

Use Requirements, Capacity, APIs & data, Reliability, Tradeoffs, and Handoff to explain decisions beyond the drawing. The diagram and all sections autosave as one revision. Export the architecture as SVG/JSON or the notes as Markdown. Submitted attempts preserve the diagram and notes together as read-only. Older notes-only attempts remain intact.

## Interview sequence

Spend about 5 minutes clarifying requirements, 5 on estimates, 15 on the main architecture and data model, 15 on failure paths/security/fairness, and 10 on tradeoffs and a handoff. These are practice suggestions within a 50-minute session, not a calibrated scoring formula.

Follow one event from ingestion through durable acceptance, matching, scheduling, a delivery attempt, and outcome inspection. Identify the points where a crash can lose work or cause a duplicate. Show durable state and explain retry ownership for every important connection.

## Failure scenario

A large customer's endpoint is unavailable for two hours. Explain retry growth, bounded concurrency, tenant fairness, expiry, the recovery surge, operator visibility, and the effect on healthy tenants. Revise the design if the scenario exposes a gap.

## Review

After submission, review requirements/capacity, durable acceptance/recovery, delivery semantics/data model, fairness, destination security, and operations/tradeoffs. Cite the preserved notes or diagram source; a component's presence alone does not establish correctness. Ratings are self-assessments, not automated architecture judgments. Voice and a conversational interviewer are not connected yet.
