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
# gVisor is the sandbox boundary, so it is pinned to one release and to the archive
# digest recorded in deploy/local-vm/runtime.json. A download that differs from the
# pinned digest is rejected, which a sidecar fetched from the same URL cannot do.
# To upgrade: set GVISOR_RELEASE and GVISOR_SHA512 together, verify the VM, then
# update the defaults here and runtime.json in the same commit.
gvisor_release=${GVISOR_RELEASE:-20261012.0}
case "$task_arch" in
  aarch64) gvisor_sha512=${GVISOR_SHA512:-3459ca3e496465e5b6a1318563ede4bb079bdf11ae93f4bb8d71df3cd2f19bfa6db7c1035d2f9e97b4f4e57c298a4f18b42af7297c048ec7e14ec819223684e4};;
  x86_64) gvisor_sha512=${GVISOR_SHA512:-ce2e1aeb853c104e854dea6644333a1dba0fbc9dd1646af97e1d013fdf810da6d4176dd96f2139d7b055e5382117c0d7c4567ebd64ed9bef47fdd15f80fd67ab};;
  *) echo "Unsupported VM architecture: $task_arch" >&2; exit 1;;
esac
case "$gvisor_release" in *[!0-9.]*|"") echo 'GVISOR_RELEASE must look like 20261012.0' >&2; exit 1;; esac
case "$gvisor_sha512" in *[!0-9a-f]*|"") echo 'GVISOR_SHA512 must be 128 hex characters' >&2; exit 1;; esac
[ "${#gvisor_sha512}" -eq 128 ] || { echo 'GVISOR_SHA512 must be 128 hex characters' >&2; exit 1; }
task_url="https://storage.googleapis.com/gvisor/releases/release/$gvisor_release/$task_arch"
curl --fail --location --retry 2 --max-time 180 --output gvisor.tar.zstd "$task_url/gvisor.tar.zstd"
printf '%s  gvisor.tar.zstd\n' "$gvisor_sha512" > gvisor.tar.zstd.sha512
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
