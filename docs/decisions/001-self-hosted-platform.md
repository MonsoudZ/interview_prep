# ADR 001: Self-hosted execution for a multi-user interview platform

Date: 2026-10-16. Product direction accepted from the user; runtime configuration proposed and awaiting integration validation.

Update: [ADR 002](002-railway-only-budget.md) supersedes the dedicated-host recommendation. Railway is the only hosting provider; no additional paid services are authorized. The existing Docker worker remains optional implementation work.

## Context

The user wants a developed interview-preparation platform that can grow beyond personal use. It includes Rails repository assessments, Ruby algorithms, system design, voice/text interviewers, and rigorous reviews. The user prefers building our own execution capability rather than using a managed sandbox as the primary dependency.

## Decision

Own the execution service and deploy it on dedicated worker infrastructure. Retain the Rails application/React workspace direction. Use established isolation technology underneath; the initial integration target is Docker with gVisor/runsc. A VM/microVM adapter remains an option if threat modeling, compatibility, or isolation testing calls for it. Do not market an untested configuration as secure.

The application owns user authentication, exercise versions, canonical artifacts, session timing, conversation, review, and learning history. Execution workers own only approved runtime operations. AI services cannot mint worker jobs or change execution policy.

### Platform modules

| Module | Responsibility |
| --- | --- |
| Identity | Accounts, workspace membership, ownership, access checks |
| Content | Versioned curricula, exercise packages, hints, verified references |
| Interviews | Modes, rules, authoritative deadlines, rounds and assistance |
| Workspaces | Source/diagram revisions, saves, checkpoints, conflict recovery |
| Execution | Leased jobs, sandbox lifecycle, terminal, execution evidence |
| Conversation | Voice/text transport, transcript, interviewer context |
| Evaluation | Versioned rubrics, evidence-linked findings, revisions |
| Learning | Skill observations, transfer/retention, recommendations |
| Operations | Quotas, usage, auditing, deletion, fleet health |

Keep domain modules in one application initially. Isolate execution as a separate trust boundary from the outset. Independent scaling is a reason to separate a process, not a reason to create a service for every table. Public signup, billing, and enterprise features are later capabilities; account ownership and authorization are foundational.

### Flow

1. Authenticate user and authorize session/exercise access.
2. Persist an immutable source snapshot and execution request transactionally with an outbox entry.
3. Dispatcher claims the request with a lease; signs a short-lived, versioned job for an authorized worker pool.
4. Worker verifies signature, expiry, source checksum, exercise allowlist, resource policy, and mandatory isolation.
5. Worker runs the approved operation and returns evidence bound to the revision.
6. Application accepts results only for the matching lease/job/revision. Duplicates are idempotent; stale results are recorded without overwriting newer state.
7. Evaluator consumes evidence separately; candidate output cannot define authoritative grading status.

The application foundation now implements authenticated accounts, immutable snapshots, a transactional execution-request queue, expiring worker leases, signing, and idempotent result ingestion. The execution request itself acts as the durable work item; a separate message-broker outbox is not needed at this stage. PostgreSQL fleet concurrency and Linux execution still need live validation. Workspace streaming/terminal, voice, and evaluation remain unimplemented.

## Growth and fairness

Start with a bounded worker pool; add hosts using centralized leases. Apply per-account concurrent-runtime, queue, time, and storage quotas. Track capacity and estimated wait time. Do not start an assessment clock while queued or preparing. Reserve resources for the advertised session once started.

Rails and Ruby share transport and accounting but use versioned images and exercise operations. System design shares sessions, voice, diagrams, evidence, and reviews without allocating a coding runtime. Mixed interview loops compose rounds through the session module.

## Costs and consequences

Self-hosting removes a managed sandbox dependency, not hosting or AI costs. We assume responsibility for kernel/runtime updates, incident response, patching, utilization, capacity, storage, and recovery. Estimate cost from a concrete hosting plan and measured workloads before provisioning. No paid host has been created.

## Evidence required before deployment

Run real starter/reference jobs on Linux/gVisor; verify hard resource limits, denied egress, no host/neighbor access, deadline/cancellation behavior, independent leak cleanup, artifact recovery, and authoritative result handling. Measure latency and cost under concurrent work. Verify application authorization, centralized leases, and per-account quotas before accepting multiple users.

## Superseded recommendation

The managed-provider comparison remains useful fallback research. Its recommendation to test Modal first is superseded by this user-directed self-hosted architecture; no Modal account is needed to continue local development.
