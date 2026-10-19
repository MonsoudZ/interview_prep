# Local VM verification

Client date: 2026-10-17. See [runtime.json](runtime.json) for versions, immutable image, dependency lock, and gVisor archive digest.

- Installed Colima/Docker tooling and created the isolated `interview` Linux VM. The generated profile contains `mounts: null`, `forwardAgent: false`, `autoActivate: false`, and `portForwarder: none`; querying `findmnt` found no virtiofs/9p/SSHFS host mounts.
- Checked the complete official gVisor archive against its published SHA-512 and installed `release-20261012.0` with companion files. Docker reports the real `runsc` runtime, Linux/cgroup v2, and CPU/memory/PID limit support.
- Built the frozen-gem Rails image from the official Ruby digest. Build took 159.048 seconds. The image inspected as Linux/ARM64, UID 1000:1000, with the expected version/exercise labels.
- Executed the existing opt-in live Rails integration test through SSH to the actual VM: **1 run, 39 assertions, zero failures/errors/skips**. It checked prepared readiness, 12 expected starter failures, reference success (12 tests/158 assertions), accepted callback identity/revision, immutable submission, UID 1000, absent Docker socket, rejected image-path writes, and blocked external IPv4 TCP.
- Started the Rails application and long-running local VM bridge with matching private keys. A previously queued preview starter job completed through real HTTP lease/callback requests and displayed 0/12 passing and the actual failures in the browser. The app showed an execution worker connected.
- Created a separate guided preview attempt, copied the trusted reference with an explicit validation comment, added its model through the file-creation UI, saved both files, prepared the VM environment, started the session, and clicked Run tests. The browser displayed **12/12 passing, 158 assertions**, matching the saved revision. This verifies the live browser/HTTP bridge/VM/callback path, not only the in-process integration test. Preview: [passing sandbox results](../../artifacts/local-vm-tests-passing.jpg).
- Created one expired, worker-owned, no-network gVisor sleep container. The independent cron reaper removed it at the next minute boundary; the reaper log recorded its exact name, and the subsequent container listing had no abandoned worker containers. The bridge did not invoke that cleanup.
- Local SSH transport regressions: **4 tests passed**, including profile injection rejection, fixed VM command, stdin-only key handling, bounded transport, and missing-key rejection before subprocess launch.
- Ordinary Rails suite: **42 runs, 337 assertions, zero failures/errors, two expected skips**. Live Linux and Railway checks remain opt-in; the Linux check was run separately as recorded above. The Railway check remains unexecuted.

The initial VM boot had a roughly two-minute first-user-session delay, then completed normally. No user files were deleted, Mac security settings changed, new subscriptions purchased, or Railway sandboxes started. Free disk after building was about 6.4 GiB and the final validation check reported 5.3 GiB.

These are actual local development observations. They do not certify resistance to every sandbox escape, deliberate resource-exhaustion case, or malicious host administrator. This VM is not a deployed public execution fleet.

## Rails curriculum and Ruby runner expansion

The current immutable image is `sha256:c9f70b151331d4153ff622d41a4d1ff92e4db3d2a86d3878e852922e353d639f` (cached dependency rebuild: 0.485 seconds). It adds four Rails starter overlays and the Ruby intervals runner/test fixtures. Reference implementations are not staged into the image. Its inventory advertises ten Rails operations and two Ruby operations; older image inventories remain limited to their installed content.

The complete real queue/VM integration passed with **3 runs, 192 assertions, no failures/errors/skips**. It executed every Rails starter/reference and Ruby starter/reference, preparation, signing, authenticated callback identity, preserved source revision, and immutable submission. Ruby reference: **12 groups, 112 assertions**, including three 100,000-input cases. New Rails references: 12 groups each, with feed 90, delivery 64, checkout 119, tenancy 153 assertions. All intentional defects were caught in trusted fixture validation (12 Rails mutations, four Ruby mutations); recorded reports live under curriculum/.

These remain execution-evidence checks. They do not certify tamper resistance, production concurrency, adversarial isolation, calibrated hiring judgments, or hosted Railway execution. No hosted compute was provisioned.

## Expanded curriculum and mock interviews — 2026-10-18

Rebuilt and activated image `sha256:900545727221727f873a3283cb886c850aaf7b9692a47f08ae97fd248405cc50` with `interview.curriculum=rails-ruby-v2` and 18 installed execution/preparation operations. The full real-VM suite passed with **3 runs, 330 assertions, zero failures/errors/skips**: all eight Rails starters/references, Ruby, queue callbacks/revision identity and the existing observable isolation probe. The bridge also ran the new support reference in the browser, reporting 12 tests/65 assertions and preserving its submitted revision inside the mock interview. Legacy images keep their smaller capability inventories.

An initial expanded live run received a callback 404. An isolated curriculum rerun with explicit lease/job existence assertions passed (1 run/241 assertions), followed by the complete successful 3-run/330-assertion run. No lease/authentication validation was relaxed. PostgreSQL concurrency and production migration safety remain outside this local proof.
