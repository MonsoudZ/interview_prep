# ADR 002: Railway-only hosting within the existing budget

Date: 2026-10-16. User constraint accepted; Railway adapter implemented locally, hosted execution and isolation unverified.

## Constraint

Railway is the user's existing hosting provider. Do not require another paid host, sandbox subscription, AI service, or voice service. Aim to fit inside the existing Railway allowance; do not interpret permission to use Railway as permission to increase the bill. The user subsequently selected a separate [Interview Studio project](../../deploy/railway/README.md), which is now created and linked. No compute services or sandboxes have been provisioned.

## Direction

Keep our Rails application, exercise contracts, snapshots, queue, leases, and result validation. The [Railway Sandboxes execution adapter](../../services/railway_worker/README.md) is now implemented as the primary hosted-runtime direction. It has local tests using a simulated VM transport and real Ruby/Node signature interoperability. The actual Railway checkpoint/bootstrap/namespace behavior has not yet been validated, so it is not a production-ready replacement for the Docker worker.

The dedicated Linux/Docker/gVisor worker remains an optional implementation for environments where that infrastructure already exists. Buying a separate Linux host or installing a local VM is no longer the next step. This supersedes ADR 001's dedicated-host deployment recommendation while retaining application ownership of execution policy.

## Runtime requirements

- Prepare a pinned Ruby/Rails environment once; evaluate templates/checkpoints instead of keeping a VM running between sessions.
- Start with one execution at a time. Create runtimes only for code execution and destroy them after completion, cancellation, or failure. Use an idle timeout as an additional cleanup measure and reconcile abandoned runtimes independently.
- Keep candidate sandboxes in Railway's `ISOLATED` network mode, without public domains, application/database secrets, or Railway API tokens. Only the trusted controller receives provider credentials.
- `ISOLATED` blocks Railway private-network access but permits outbound internet. The implementation additionally requires a non-root network/PID/mount namespace and a trusted isolation probe before staging candidate code. Live support for those kernel operations and adversarial isolation remain unverified; the adapter fails closed if the probe fails.
- Validate actual resource controls, Rails readiness, starter/reference results, revision binding, timeout/cancellation, cleanup, and measured costs. Existing Docker-specific live tests cannot establish Railway isolation.

## Cost policy and next step

Railway sandbox VM usage is metered per second and uses the same included allowance as other Railway workloads. CPU, memory (including OS/cache), and outbound traffic consume usage; waiting VMs still incur memory usage. Destroyed VMs incur no further compute usage. Railway-only does not mean free or a guaranteed unchanged bill.

Before launching a hosted experiment, identify the intended existing project, plan allowance, current usage, and budget available after the user's other workloads. Prepare the adapter locally first. Do not provision paid resources or change workspace-wide spending limits as an implicit part of setup; those limits can affect the user's other applications.

Keep automated tests, explicit rubrics, verified references, and manual review available without paid AI. AI feedback and voice remain product goals, but their no-additional-cost implementation is unresolved. Do not present them as implemented or silently introduce a paid API dependency.

## Sources

Official documentation checked 2026-10-16:

- [Railway Sandboxes](https://docs.railway.com/sandboxes)
- [Sandbox quickstart](https://docs.railway.com/sandboxes/quickstart)
- [Railway plans and VM billing](https://docs.railway.com/pricing/plans)
- [Railway cost controls](https://docs.railway.com/pricing/cost-control)
