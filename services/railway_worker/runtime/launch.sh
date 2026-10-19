#!/bin/bash
set -euo pipefail
seconds=${1:-}
mode=${2:-tests}
[[ "$seconds" =~ ^[0-9]+$ ]] && (( seconds >= 1 && seconds <= 60 )) || exit 70
[[ "$mode" = tests || "$mode" = prepare || "$mode" = probe ]] || exit 70
test "$(id -u)" = 0 || exit 70
if [[ "$mode" = probe ]]; then
  exec 3</dev/null
else
  exec 3</opt/runner/job.json
  rm /opt/runner/job.json
fi
# timeout and the VM controller both bound execution. A new PID namespace also
# destroys descendants when its init process exits. No candidate text is shell code here.
exec timeout --signal=TERM --kill-after=3s "$seconds" \
  unshare --mount --net --pid --fork --mount-proc \
  /bin/bash /opt/runner/isolated.sh "$mode" <&3
