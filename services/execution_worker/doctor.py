#!/usr/bin/env python3
"""Read-only host/image readiness check. A pass is not isolation certification."""
import argparse
import json
import os
import platform
import shutil
import sys

from worker import preflight, inspect_image


def diagnose(image, docker=None):
    docker = docker or shutil.which("docker")
    report = {"host": platform.system(), "docker_available": bool(docker),
              "ready": False, "live_execution_tested": False, "issues": []}
    if not docker:
        report["issues"].append("Docker is not installed; configure a dedicated Linux worker or local Linux VM.")
        return report
    try:
        report["daemon"] = preflight(docker)
        report["image"] = inspect_image(docker, image)
    except Exception as error:
        report["issues"].append(str(error))
        return report
    report["ready"] = True
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default=os.environ.get("INTERVIEW_WORKER_IMAGE", ""))
    args = parser.parse_args()
    result = diagnose(args.image)
    print(json.dumps(result, indent=2))
    sys.exit(0 if result["ready"] else 2)
