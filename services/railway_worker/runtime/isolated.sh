#!/bin/bash
set -euo pipefail
mount --make-rprivate /
mount -t tmpfs -o size=64m,nosuid,nodev,noexec,mode=1777 tmpfs /tmp
ulimit -u 128
ulimit -n 1024
ulimit -f 65536
ulimit -v 1572864
cd /workspace
mode=${1:?}
if [[ "$mode" = probe ]]; then
  runner=(/opt/runner/probe.rb)
else
  runner=(-r /opt/runner/probe.rb /opt/runner/run.rb)
fi
runner_args=()
[[ "$mode" = prepare ]] && runner_args+=(--prepare)
exec setpriv --reuid=20000 --regid="$(id -g interview)" --clear-groups \
  --bounding-set=-all --inh-caps=-all --ambient-caps=-all --no-new-privs \
  env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp LANG=C.UTF-8 \
  RAILS_ENV=test BUNDLE_PATH=/opt/bundle BUNDLE_APP_CONFIG=/opt/bundle-config \
  BUNDLE_FROZEN=true BUNDLE_FORCE_RUBY_PLATFORM=true \
  ruby "${runner[@]}" "${runner_args[@]}"
