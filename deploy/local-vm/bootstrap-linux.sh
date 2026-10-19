#!/bin/sh
# Trusted setup for the dedicated development VM. Never run inside candidate jobs.
set -eu
if command -v apk >/dev/null 2>&1; then
  sudo apk add --no-cache python3 curl tar zstd
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y python3 curl tar zstd cron
else
  echo 'Unsupported VM package manager' >&2
  exit 1
fi
task_dir=$(mktemp -d)
trap 'rm -rf "$task_dir"' EXIT
cd "$task_dir"
task_arch=$(uname -m)
case "$task_arch" in aarch64|x86_64) ;; *) exit 1;; esac
task_url="https://storage.googleapis.com/gvisor/releases/release/latest/$task_arch"
curl --fail --location --retry 2 --max-time 180 --output gvisor.tar.zstd "$task_url/gvisor.tar.zstd"
curl --fail --location --retry 2 --max-time 30 --output gvisor.tar.zstd.sha512 "$task_url/gvisor.tar.zstd.sha512"
sha512sum -c gvisor.tar.zstd.sha512
sudo tar --zstd -xf gvisor.tar.zstd -C /usr/local/bin
sudo /usr/local/bin/runsc install
if command -v rc-service >/dev/null 2>&1; then
  sudo rc-service docker restart
else
  sudo systemctl restart docker
fi
sudo mkdir -p /opt/interview/verification
sudo cp gvisor.tar.zstd.sha512 /opt/interview/verification/gvisor.sha512
runsc --version
docker info --format '{{.OSType}} {{.Architecture}}; runsc={{index .Runtimes "runsc"}}'
