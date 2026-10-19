# ADR 003: Local Linux VM for development execution

Date: 2026-10-17. User selected local Linux VM development and clarified that Railway is already their paid hosting provider.

Use a dedicated Colima Linux VM on the Apple Silicon Mac for the Docker/gVisor execution worker. Keep Railway as the hosted provider; no additional hosting subscription is required. This changes the development path from waiting for Railway sandbox bootstrap approval to using the existing self-hosted worker locally.

The VM and image are now installed and the real Rails integration test passes. A Mac-side bridge forwards signed jobs over SSH stdin to the strict Linux worker. Candidate code executes in gVisor, never as a Mac Ruby subprocess. No Mac folders or SSH agent are shared with the VM. The app and bridge use private matching keys. The independent VM cron watchdog cleans expired worker-owned containers.

See [setup and usage](../../deploy/local-vm/README.md), [verification](../../deploy/local-vm/VERIFICATION.md), and [runtime provenance](../../deploy/local-vm/runtime.json). The VM is available while this Mac is awake and running it; hosted multi-user capacity and public security validation remain later deployment work.

The separate Interview Studio Railway project stays available for eventual app hosting. The previously blocked billable Railway sandbox bootstrap remains unexecuted; this decision does not bypass that approval or change workspace-wide spending limits.
