# Central Mac Studio installation

Use the M4 Max Studio as the central app, database, Linux execution worker, and local model host. Open that same app from either computer. A second checkout on the laptop is useful for development; it does not synchronize accounts or practice history.

The M4 Max Studio now has `qwen3.5:27b` installed and the app connected in review-only mode. Initial real-model checks are recorded in [verification](VERIFICATION.md); broad review calibration and the Studio's Linux execution worker setup remain outstanding. No Railway compute or paid inference is provisioned.

## 1. Transfer the code

On the Studio, clone the repository and enter its directory:

```sh
git clone https://github.com/MonsoudZ/interview_prep.git
cd interview_prep
```

For later source updates, use `git pull --ff-only` from a clean checkout, then install any updated dependencies and run database migrations before restarting the app. Git does not transfer practice history or local worker configuration.

Alternatively, create a code-only archive from the laptop repository root:

```sh
python3 deploy/studio/manage.py package --output artifacts/studio-interview.tar.gz
```

Transfer the archive and its `.sha256` sidecar to the Studio using AirDrop or another private transfer. Verify it with `shasum -a 256 -c studio-interview.tar.gz.sha256`, then extract it with `tar -xzf studio-interview.tar.gz`. Run the following commands from the extracted `interview-studio` directory. The package excludes practice databases, worker credentials, environment files, logs, caches, and artifacts. Generate new worker keys on the Studio.

## 2. Prepare the native app and Linux worker

Install Ruby 4.0.1, Bundler, Python 3, Colima, and the Docker CLI on the Studio. Use the [local VM recreation instructions](../local-vm/README.md#recreate-or-update) to create the dedicated `interview` profile, register gVisor in Colima's persistent configuration, bootstrap Linux, stage the worker files, install the watchdog, and build the image. The model runs on macOS; only candidate code runs inside the Linux sandbox.

Use the **actual image ID produced on the Studio**, which may differ from the laptop's image ID. The VM guide documents the pinned Ruby base and its tested isolation configuration. Do not share the Studio home directory with the VM.

Install the app dependencies:

```sh
cd apps/platform
bundle install
ruby bin/rails db:prepare
cd ../..
```

## 3. Install and connect a local model

Install [Ollama for macOS](https://ollama.com/download/mac). Quit its background app first if it is already serving, then run a native server in a separate terminal:

```sh
OLLAMA_NO_CLOUD=1 ollama serve
```

Keep the default loopback binding. The app does not expose port 11434 or send submissions to a paid fallback. `OLLAMA_NO_CLOUD=1` disables Ollama's cloud features for this server process; setting it in an unrelated terminal does not reconfigure an already running server. See [Ollama's FAQ](https://docs.ollama.com/faq).

In another terminal, download the first model to evaluate:

```sh
ollama pull qwen3.5:27b
```

[Qwen3.5 27B](https://ollama.com/library/qwen3.5:27b) is the initial candidate for this 64 GB machine. Its actual latency, memory use, and review accuracy still need measurement on this hardware. Start with one review at a time and a 32K context. The worker deliberately rejects oversized input instead of silently truncating the submission. A 64K setting is available after measuring memory and response time.

Configure the app using the Studio's newly built image ID:

```sh
python3 deploy/studio/manage.py configure --image sha256:REPLACE_WITH_ACTUAL_64_HEX_IMAGE_ID --model qwen3.5:27b --context 32768
python3 deploy/studio/manage.py doctor
colima -p interview start
python3 services/local_vm/dev.py start
```

`configure` enables the reviewer's reasoning mode by default; pass `--thinking off` for the faster setting, or override one start with `python3 services/local_vm/dev.py start --review-thinking off`. Reasoning mode takes several minutes per review on this hardware; the app keeps a review leased while its worker is heartbeating, up to twenty minutes. `configure` writes fresh private credentials and a unique cookie name under ignored `.state` storage. It does not start servers or download models. `doctor` checks local prerequisites; the launcher also checks that the configured model is installed and has a recorded digest. An unavailable model leaves practice available with the reviewer marked offline. Start Ollama and restart the launcher to reconnect it.

Open `http://127.0.0.1:3100/` on the Studio. Submit an attempt, open its review, and choose **Generate review**. Feedback is requested explicitly and covers the frozen submission. It has its own report; it never fills in or replaces self-assessment ratings.

If the Linux execution worker is not installed yet, start the app and reviewer independently:

```sh
python3 deploy/studio/manage.py configure --review-only --model qwen3.5:27b --context 32768
python3 services/local_vm/dev.py start --review-only
```

This requires the native app dependencies and prepared database from step 2, plus a running Ollama server. System-design practice and reviews of existing submissions are available; sandboxed code execution requires the Linux worker. Later, configure its actual image ID and start without `--review-only`. Reconfiguration preserves existing credentials and any configured image ID.

## 4. Use the Studio from the laptop

Enable macOS Remote Login for your chosen Studio account, then use an SSH tunnel from the laptop:

```sh
ssh -N -L 3101:127.0.0.1:3100 YOUR_STUDIO_USER@YOUR_STUDIO_HOST
```

Open `http://localhost:3101/` on the laptop. Both browsers now use the Studio's app and database. Port 3101 avoids colliding with a laptop development server. SSH encrypts the connection; the app and model remain bound to Studio loopback. Your actual hostname/account must replace the placeholders. The Studio must remain awake and the launcher, VM, and model server must remain running. For access away from home, use an established private network connection rather than forwarding these ports publicly.

## 5. Preserve existing laptop practice data

If you want the existing accounts, submissions, execution results, and self-reviews on the Studio, make a consistent SQLite backup on the laptop:

```sh
python3 deploy/studio/manage.py backup --output /PRIVATE_PATH/interview-practice.sqlite3
```

The command uses SQLite's backup API, including committed WAL data, and creates a mode-0600 file. Transfer it privately; it contains accounts and submitted work. It is separate from the code archive.

Stop the Studio launcher before restoring into a fresh installation:

```sh
python3 deploy/studio/manage.py restore --from-file /PRIVATE_PATH/interview-practice.sqlite3
cd apps/platform
ruby bin/rails db:migrate
cd ../..
python3 services/local_vm/dev.py start
```

Restore refuses to overwrite a destination containing accounts or sessions. Do not copy raw SQLite files while the app is running, or copy the laptop's worker keys. Sign in again on the Studio app; sessions are intentionally specific to its new secret. Keep the laptop backup until the transferred history is checked. After this move, practice through the Studio app so history stays in one place.

## Review evidence and accuracy

New review packets include relevant, dated summaries of public Google and Amazon preparation/review guidance, Apple engineering context for Rails/design, and Ruby language documentation for Ruby tasks. The [guidance catalog](../../curriculum/reviewer_guidance/README.md) distinguishes interview advice from engineering descriptions and records our local coaching interpretations. Completed reviews disclose their saved sources. This supplies inference context; it does not fine-tune the model or change the exercise rubric. It works in review-only mode without a Linux worker.

Run repeatable local model checks without writing practice history:

```sh
python3 services/review_worker/evaluate.py --output artifacts/reviewer-evaluation/run-001
```

Choose a new output directory for each run. See the [evaluation guide](../../services/review_worker/evaluation/README.md) for expected outcomes and the distinction between report validity and semantic accuracy.

The worker supplies the published exercise, senior rubric, submitted source/design files, a reference alternative where available, assistance history, and recent test results from the same revision. Source citations must exist in that frozen submission; cited run IDs must belong to its packet. Invalid reports are rejected, and model name, digest, rubric version, and prompt version are recorded. Inputs are treated as untrusted data; the model has no execution tools. Callback receipts are saved privately and retried without rerunning inference.

These checks validate report structure and provenance. They cannot prove the model's conclusions. Feedback is advisory, with no hiring verdict or claim of FAANG calibration. The model is not trained merely by supplying exercise documents.

Before relying on judgments, compare reviews against human-labeled examples for Rails, Ruby, and system design: strong submissions, known defects, and valid alternative designs. Hold some examples out of prompts and future tuning. Measure missed defects, false positives, citation accuracy, unsupported requirements, and latency. Revise the rubric/context first; consider fine-tuning only after collecting reviewed examples and retaining a held-out evaluation set. This calibration remains outstanding until the Studio model is available.

## Verification commands

```sh
python3 -m unittest discover -s services/review_worker/tests -v
python3 -m unittest discover -s deploy/studio/tests -v
cd apps/platform
ruby bin/rails test
node --test test/frontend/*.test.mjs
```

The Python worker transport test uses local fixture HTTP servers and needs loopback socket access. Its responses are labeled synthetic transport fixtures; they do not assess model quality. See [verification status](VERIFICATION.md) for what was actually checked.
