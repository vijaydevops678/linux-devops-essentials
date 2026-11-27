#!/usr/bin/env bash
#
# process-monitor.sh - Quick view of what is running and what is hurting the server.
#
# Shows load vs CPU cores, top processes by CPU and memory, processes per user
# and zombie processes. Optionally checks that a process is running (-w) or
# alerts on any process above a CPU threshold (-c).
#
# Usage:   ./process-monitor.sh [-n count] [-w process_name] [-c cpu_percent]
# Example: ./process-monitor.sh -n 10 -w nginx -c 90
# Exit code: 0 = OK, 1 = watched process missing or CPU threshold exceeded

set -euo pipefail

COUNT=5
WATCH=""
CPU_LIMIT=""
PROBLEMS=0

usage() {
  cat <<EOF
Usage: ${0##*/} [-n count] [-w process_name] [-c cpu_percent]

  -n count         Number of top processes to show (default: $COUNT)
  -w process_name  Exit with an error if this process is not running
  -c cpu_percent   Exit with an error if any process uses more CPU than this
  -h               Show this help
EOF
}

while getopts ":n:w:c:h" opt; do
  case "$opt" in
    n) COUNT=$OPTARG ;;
    w) WATCH=$OPTARG ;;
    c) CPU_LIMIT=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

[[ "$COUNT" =~ ^[0-9]+$ ]] || { echo "-n must be a number" >&2; exit 1; }
if [[ -n "$CPU_LIMIT" && ! "$CPU_LIMIT" =~ ^[0-9]+$ ]]; then
  echo "-c must be a whole number" >&2; exit 1
fi

header() { printf '\n== %s ==\n' "$1"; }

echo "Process report for $(hostname) at $(date '+%F %T')"

header "Load average"
cores=$(nproc)
read -r load1 load5 load15 _ < /proc/loadavg
echo "  1 min: $load1   5 min: $load5   15 min: $load15   (CPU cores: $cores)"
if awk -v l="$load1" -v c="$cores" 'BEGIN {exit !(l > c)}'; then
  echo "  WARNING: load is higher than the number of cores; processes are waiting for CPU"
fi

header "Top $COUNT by CPU"
ps -eo pid,user,%cpu,%mem,etime,comm --sort=-%cpu | head -n $((COUNT + 1)) || true

header "Top $COUNT by memory"
ps -eo pid,user,%cpu,%mem,rss,comm --sort=-%mem | head -n $((COUNT + 1)) || true

header "Processes per user"
ps -eo user= | sort | uniq -c | sort -rn | head -n 5 | sed 's/^/ /' || true
echo "  Total processes: $(ps -e --no-headers | wc -l)"

header "Zombie processes"
zombies=$(ps -eo pid,ppid,stat,comm --no-headers | awk '$3 ~ /^Z/' || true)
if [[ -z "$zombies" ]]; then
  echo "  none"
else
  echo "  PID PPID STAT COMMAND"
  echo "$zombies" | sed 's/^/  /'
  echo "  Tip: zombies disappear when their parent (PPID) reaps them or is restarted."
fi

if [[ -n "$WATCH" ]]; then
  header "Watch: $WATCH"
  if pids=$(pgrep -x "$WATCH"); then
    echo "  OK: running (PID: $(echo "$pids" | tr '\n' ' '))"
  else
    echo "  PROBLEM: $WATCH is NOT running"
    PROBLEMS=$((PROBLEMS + 1))
  fi
fi

if [[ -n "$CPU_LIMIT" ]]; then
  header "Processes above ${CPU_LIMIT}% CPU"
  hot=$(ps -eo pid,%cpu,comm --no-headers --sort=-%cpu | awk -v t="$CPU_LIMIT" '$2 > t' || true)
  if [[ -z "$hot" ]]; then
    echo "  none"
  else
    echo "$hot" | sed 's/^/  /'
    PROBLEMS=$((PROBLEMS + 1))
  fi
fi

(( PROBLEMS == 0 )) || exit 1
