#!/usr/bin/env bash
#
# service-watchdog.sh - Make sure critical systemd services stay up.
#
# For each service: if it is not active, restart it, wait, and check again.
# Logs every action and shows the last journal lines of anything that fails.
# Run it from a systemd timer or cron (see service-watchdog.timer).
#
# Usage:   sudo ./service-watchdog.sh [-c] [-l logfile] service [service ...]
# Example: sudo ./service-watchdog.sh nginx docker ssh
# Exit code: 0 = all services active, 1 = at least one is down

set -euo pipefail

CHECK_ONLY=false
LOG_FILE=/var/log/service-watchdog.log
WAIT_SECONDS=3
FAILED=0

usage() {
  cat <<EOF
Usage: ${0##*/} [-c] [-l logfile] service [service ...]

  -c          Check only: report, never restart
  -l logfile  Log file (default: $LOG_FILE)
  -h          Show this help
EOF
}

log() {
  local line
  line="$(date '+%F %T') $*"
  echo "$line"
  if [[ -w "$LOG_FILE" || ( ! -e "$LOG_FILE" && -w "$(dirname "$LOG_FILE")" ) ]]; then
    echo "$line" >> "$LOG_FILE"
  fi
}

while getopts ":cl:h" opt; do
  case "$opt" in
    c) CHECK_ONLY=true ;;
    l) LOG_FILE=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

[[ $# -gt 0 ]] || { usage; exit 1; }
[[ -d /run/systemd/system ]] || { echo "systemd is not running on this machine" >&2; exit 1; }
if [[ "$CHECK_ONLY" == false && $EUID -ne 0 ]]; then
  echo "Run as root to restart services (or use -c to only check)" >&2
  exit 1
fi

for svc in "$@"; do
  if systemctl is-active --quiet "$svc"; then
    log "OK        $svc is active"
    continue
  fi

  state=$(systemctl is-active "$svc" 2>/dev/null || true)
  if [[ "$CHECK_ONLY" == true ]]; then
    log "DOWN      $svc is ${state:-unknown}"
    FAILED=$((FAILED + 1))
    continue
  fi

  log "RESTART   $svc is ${state:-unknown}, restarting"
  systemctl restart "$svc" 2>/dev/null || true
  sleep "$WAIT_SECONDS"

  if systemctl is-active --quiet "$svc"; then
    log "RECOVERED $svc is active again"
  else
    log "FAILED    $svc did not come back. Last log lines:"
    journalctl -u "$svc" -n 10 --no-pager 2>/dev/null | sed 's/^/          /' || true
    FAILED=$((FAILED + 1))
  fi
done

(( FAILED == 0 )) || exit 1
