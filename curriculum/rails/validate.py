#!/usr/bin/env python3
"""Run trusted published starters/references in temporary directories. Never evaluate user snapshots here.
Use the real VM integration for candidate execution/isolation verification.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CURRICULUM = Path(__file__).parent

def run(slug, reference=False, mutation=None, prepare=False):
    with tempfile.TemporaryDirectory(prefix="interview-published-") as directory:
        root = Path(directory)
        workspace = root / "workspace"
        workspace.mkdir()
        script = (ROOT / "services/execution_worker/image/run.rb").read_text()
        script = script.replace('"/workspace"', json.dumps(str(workspace)))
        script = script.replace('"/opt/exercise/*"', json.dumps(str(ROOT / "experiments/rails-runtime/template/*")))
        script = script.replace('/opt/curriculum/', str(CURRICULUM) + '/')
        entrypoint = root / "run.rb"
        entrypoint.write_text(script)
        source = CURRICULUM / slug / "starter"
        files = {str(p.relative_to(source)): p.read_text() for p in source.rglob("*.rb")
                 if str(p.relative_to(source)).startswith("app/") or str(p.relative_to(source)) in ("config/routes.rb", "db/schema.rb")}
        if reference:
            overlay = CURRICULUM / slug / "reference"
            files.update({str(p.relative_to(overlay)): p.read_text() for p in overlay.rglob("*.rb")})
        if mutation:
            path, old, new = mutation
            assert old in files[path], f"Mutation did not match {slug}/{path}"
            files[path] = files[path].replace(old, new)
        payload = {"files": {p: base64.b64encode(s.encode()).decode() for p, s in files.items()}}
        env = os.environ.copy()
        env.pop("BUNDLE_GEMFILE", None)
        env["BUNDLE_APP_CONFIG"] = str(root / "bundler")
        return subprocess.run(["ruby", str(entrypoint), "--exercise", slug] + (["--prepare"] if prepare else []),
                              input=json.dumps(payload), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              cwd=workspace, env=env, timeout=40)

MUTATIONS = {
 "support-escalations": [("app/controllers/escalations_controller.rb", "organization_id: agent.organization_id", "organization_id: [7, 8]"), ("app/controllers/escalations_controller.rb", 'agent.role == "supervisor"', "true")],
 "invoice-amendments": [("app/controllers/invoices_controller.rb", "version: version + 1", "version: version + 2"), ("db/schema.rb", "add_index :invoice_amendments, [:invoice_id, :version], unique: true", "# no unique index")],
 "safe-backfill": [("app/services/customer_email_backfill.rb", "normalized_email: nil, email: row.email", "normalized_email: nil"), ("app/services/customer_email_backfill.rb", ".limit(batch_size)", "")],
 "tenant-projects": [
  ("app/controllers/projects_controller.rb", "Project.where(organization_id: @user.organization_id)", "Project.all"),
  ("app/controllers/projects_controller.rb", 'unless @user.role == "editor"', 'unless true'),
  ("app/controllers/projects_controller.rb", 'project.update!(name: name)', 'project.update!(name: name, organization_id: input[:organization_id] || project.organization_id)')],
 "idempotent-checkout": [
  ("app/controllers/orders_controller.rb", "existing = Order.find_by(customer_id: customer_id, idempotency_key: key)", "existing = Order.find_by(idempotency_key: key)"),
  ("app/controllers/orders_controller.rb", 'Product.transaction do', 'begin'),
  ("db/schema.rb", 'add_index :orders, [:customer_id, :idempotency_key], unique: true', '# missing unique index')],
 "delivery-retries": [
  ("app/jobs/delivery_job.rb", 'return unless delivery && delivery.status == "pending"', 'return unless delivery'),
  ("app/jobs/delivery_job.rb", 'code != 429', 'true'),
  ("app/jobs/delivery_job.rb", 'rescue DeliveryTransport::Unavailable', 'rescue StandardError')],
 "activity-feed": [
  ("app/controllers/feed_controller.rb", 'Post.where(organization_id: organization.to_i)', 'Post.all'),
  ("app/controllers/feed_controller.rb", '.preload(:author)', ''),
  ("app/controllers/feed_controller.rb", 'counts.fetch(post.id, 0)', 'post.comments.count')]
}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mutations", action="store_true")
    parser.add_argument("--exercise", action="append", help="Validate only these published exercise slugs")
    args = parser.parse_args()
    report = []
    for manifest in sorted(CURRICULUM.glob("*/exercise.json")):
        slug = manifest.parent.name
        if args.exercise and slug not in args.exercise:
            continue
        test_count = json.loads(manifest.read_text())["test_count"]
        for label, reference, prepare in [("prepare", False, True), ("starter", False, False), ("reference", True, False)]:
            result = run(slug, reference=reference, prepare=prepare)
            summary = re.search(r"\d+ runs, \d+ assertions, \d+ failures, \d+ errors, \d+ skips", result.stdout)
            valid = result.returncode == 0 if label != "starter" else result.returncode != 0 and bool(summary)
            if label == "reference":
                valid = valid and bool(re.search(rf"{test_count} runs, \d+ assertions, 0 failures, 0 errors, 0 skips", result.stdout))
            if not valid:
                print(result.stdout)
                raise RuntimeError(f"{slug}: invalid {label}")
            item = {"exercise": slug, "variant": label, "summary": summary[0] if summary else "READY"}
            report.append(item); print(json.dumps(item), flush=True)
        if args.mutations:
            for mutation in MUTATIONS.get(slug, []):
                result = run(slug, reference=True, mutation=mutation)
                assert result.returncode != 0, f"Surviving mutation: {slug} {mutation}"
                # Reject mutants caught only by load/syntax errors, rather than behavior checks.
                summary = re.search(rf"{test_count} runs, \d+ assertions, ([1-9]\d*) failures, \d+ errors, 0 skips", result.stdout)
                if not summary:
                    print(result.stdout)
                    raise RuntimeError(f"Mutation did not produce a behavioral failure: {slug} {mutation}")
                item = {"exercise": slug, "variant": "mutation", "defect": mutation[1], "summary": summary[0]}
                report.append(item); print(json.dumps(item), flush=True)
    if args.exercise:
        return
    (CURRICULUM / "validation.json").write_text(json.dumps(report, indent=2) + "\n")

if __name__ == "__main__":
    main()
