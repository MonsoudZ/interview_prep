# Interview Studio Railway project

The user selected a separate Interview Studio project on 2026-10-16. It was created in their existing Railway workspace and this repository's directory was linked to it through the Railway CLI. No existing project was renamed, relinked globally, or deployed over.

- [Project dashboard](https://railway.com/project/e03c6b7e-112f-4ca1-9a82-e7b6f98faf24)
- Production environment: `d43db596-0489-4323-b75b-b8ed68dd3407`
- Project/environment identifiers: [project.json](project.json); these are not credentials.

Verified immediately after creation: the project has no services. No app/database/worker service or sandbox was provisioned, and no spending limit was changed.

The official SDK successfully authenticated to this environment using the existing CLI login held only in process memory for a read-only checkpoint lookup. No new API token was created or persisted. The expected Rails checkpoint does not exist yet. A subsequent request to run the one-off bootstrap was rejected by automatic approval review because sandbox compute can incur charges and the user's no-extra-cost constraint does not approve that concrete spend or confirm a zero-cost allowance. The bootstrap did not execute; explicit approval for the bounded validation is pending.

## Configuration still needed

The [execution adapter](../../services/railway_worker/README.md) accepts this environment UUID through `RAILWAY_ENVIRONMENT_ID`. Its API/bridge/signing keys must be configured securely; this file deliberately contains no credentials. The application service and worker have not been deployed.

The older global CLI remains installed unchanged. Railway CLI 5.70.0 was installed into `/private/tmp/interview-railway-cli` solely for read-only usage/plan checks; the temporary path may disappear. A current CLI can read:

```sh
railway usage --workspace eaf5eccb-b21e-4214-8fc9-da182333b466 --json
```

Usage is shared across the workspace. Confirm live allowance immediately before any runtime build/test or deployment. A separate project does not create a separate free resource allowance. Do not alter other projects or workspace-wide limits to make room.
