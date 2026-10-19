# Rails runtime experiment

A working, trusted-local-code experiment for the first technical validation milestone. This is not the hosted application, a browser workspace, a secure sandbox, or a production grading service. Never use this runner to execute arbitrary uploaded code on your computer or application server.

## Included

- A minimal real Rails API repository with SQLite, requirements, and exactly 12 integration tests.
- A starter with placeholder actions that intentionally fails all 12 tests.
- A reference implementation in a separate directory.
- A repeatable driver that prepares a project, runs tests, applies the reference, introduces a regression, checkpoints/restores source, checks checkpoint integrity, and verifies process timeout handling.
- Machine-readable measured output in [results/latest.json](results/latest.json).

No global gems are installed by this experiment. The lockfile was resolved against locally installed dependencies. Rails 8.1.4, SQLite gem 2.9.6, and Minitest 6.0.6 are pinned; see the complete lockfile for transitive dependencies. This is an observed working local configuration, not a researched production version recommendation.

## Run

From the repository root, with Python 3 and the locked Ruby gems installed:

```sh
python3 experiments/rails-runtime/experiment.py demo --ruby "$(ruby -rrbconfig -e 'print RbConfig.ruby')"
```

The Ruby argument must identify the actual executable, because the driver deliberately supplies a minimal environment rather than depending on shell/rbenv configuration.

Each run creates a unique directory under `.work/` and writes `results/latest.json`. The driver exits unsuccessfully if the expected failure/pass transitions, recovery, integrity rejection, or timeout do not occur. It does not clean previous runs; they remain available for inspecting artifacts. `.work/` is ignored by Git.

## Edit an exercise manually

Read the latest result's `run_id`. Your working copy is `.work/<run_id>/workspace`. After the demo it contains the deliberately broken controller; `.work/<run_id>/recovered` contains the recovered correct implementation. Neither is a hidden solution during this technical experiment.

To start a fresh exercise manually, copy `template/` to a new directory, then run the following inside the copy:

```sh
bundle check
bundle exec ruby bin/prepare.rb
bundle exec ruby -Itest test/integration/events_test.rb
```

`bin/prepare.rb` recreates the exercise database and destroys its previous rows. It is intended for fresh readiness/recovery in this experiment, not for preserving a running candidate database.

## Recovery contract

Checkpoints include source and dependency lockfile, with per-file SHA-256 hashes and an overall revision. Restore verifies hashes and creates a new directory. Database, logs, temporary files, and local bundler config are excluded. The database is rebuilt from schema. This proves source recovery across independent Rails processes, not recovery of live database state or authenticity against an attacker able to rewrite both the snapshot and its manifest.

## Remaining validation

- Select a hosted isolation platform and validate security boundaries and quotas.
- Measure cold/warm startup including image provisioning and dependency handling.
- Connect browser editor and terminal to one versioned filesystem.
- Persist checkpoints externally and validate reconnect/timeout submission behavior.
- Enforce production output limits, process accounting, network policies, and storage limits.
- Run authoritative final grading outside the candidate's ability to alter results.
- Measure hosted cost and concurrency.

The host has no Docker or Podman executable available. The experiment uses ordinary local processes and does not claim container or VM isolation.

Rails implementation/testing references: [API-only applications](https://guides.rubyonrails.org/api_app.html) and [testing Rails applications](https://guides.rubyonrails.org/testing.html).
