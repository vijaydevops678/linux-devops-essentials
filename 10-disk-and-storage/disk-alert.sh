#!/usr/bin/env bash
#
# disk-alert.sh - Alert before a disk fills up.
#
# Checks space and inode usage of every real filesystem. Anything at or above
# the threshold is reported, and optionally sent to a Slack/Teams/Discord
# style webhook. Designed for cron.
#
# Usage:   ./disk-alert.sh [-t percent] [-i inode_percent] [-w webhook_url]
# Example: ./disk-alert.sh -t 85 -w https://hooks.slack.com/services/XXX
# Exit code: 0 = all below threshold, 1 = at least one alert

set -euo pipefail

THRESHOLD=80
INODE_THRESHOLD=80
WEBHOOK=""
ALERTS=()
EXCLUDE=(-x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs)

usage() {
  cat <<EOF
Usage: ${0##*/} [-t percent] [-i inode_percent] [-w webhook_url]

  -t percent        Space usage that triggers an alert (default: $THRESHOLD)
  -i inode_percent  Inode usage that triggers an alert (default: $INODE_THRESHOLD)
  -w webhook_url    Send alerts to this webhook (Slack-compatible JSON)
  -h                Show this help
EOF
}

while getopts ":t:i:w:h" opt; do
  case "$opt" in
    t) THRESHOLD=$OPTARG ;;
    i) INODE_THRESHOLD=$OPTARG ;;
    w) WEBHOOK=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
for n in "$THRESHOLD" "$INODE_THRESHOLD"; do
  [[ "$n" =~ ^[0-9]+$ ]] && (( n <= 100 )) || { echo "Thresholds must be 0-100" >&2; exit 1; }
done

printf '%-28s %6s %6s  %s\n' MOUNT USED% INODE% STATUS

while read -r mount used; do
  used=${used%\%}
  inode=$(df -Pi "$mount" 2>/dev/null | awk 'NR == 2 {print $5}')
  inode=${inode%\%}
  [[ "$inode" =~ ^[0-9]+$ ]] || inode=0

  status="OK"
  if (( used >= THRESHOLD )); then
    status="ALERT space"
    ALERTS+=("$mount is ${used}% full")
  fi
  if (( inode >= INODE_THRESHOLD )); then
    status="ALERT inodes"
    ALERTS+=("$mount has used ${inode}% of its inodes")
  fi
  printf '%-28s %5s%% %5s%%  %s\n' "$mount" "$used" "$inode" "$status"
done < <(df -P "${EXCLUDE[@]}" 2>/dev/null | awk 'NR > 1 {print $6, $5}')

if [[ ${#ALERTS[@]} -eq 0 ]]; then
  echo "All filesystems are below ${THRESHOLD}% space and ${INODE_THRESHOLD}% inodes."
  exit 0
fi

message="Disk alert on $(hostname): $(IFS=';'; echo "${ALERTS[*]}")"
echo
echo "$message"
echo "Find what is using the space: ../02-files-and-directories/find-large-files.sh <mount>"

if [[ -n "$WEBHOOK" ]]; then
  escaped=${message//\\/\\\\}
  escaped=${escaped//\"/\\\"}
  if curl -fsS -m 10 -X POST -H 'Content-Type: application/json' \
       --data "{\"text\": \"$escaped\"}" "$WEBHOOK" >/dev/null; then
    echo "Alert sent to webhook."
  else
    echo "Could not send the webhook alert." >&2
  fi
fi
exit 1
