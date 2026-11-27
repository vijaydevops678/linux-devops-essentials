#!/usr/bin/env bash
#
# health-check.sh - Full server health report with OK / WARN / CRIT status and alerts.
#
# Checks CPU, memory, swap, load, every disk, zombie processes and failed
# systemd units against thresholds. Prints a report, appends a one-line
# summary to a log, and sends a webhook alert when anything is not OK.
#
# Exit codes follow the Nagios convention, so monitoring tools understand them:
#   0 = OK, 1 = WARNING, 2 = CRITICAL
#
# Usage:   ./health-check.sh [-q] [-l logfile] [-w webhook_url]
# Example: ./health-check.sh
#          ./health-check.sh -q -l /var/log/health-check.log -w https://hooks.slack.com/services/XXX
#
# Thresholds can be changed with environment variables, e.g. CPU_WARN=70 ./health-check.sh

set -euo pipefail

CPU_WARN=${CPU_WARN:-80};   CPU_CRIT=${CPU_CRIT:-95}
MEM_WARN=${MEM_WARN:-80};   MEM_CRIT=${MEM_CRIT:-95}
SWAP_WARN=${SWAP_WARN:-50}; SWAP_CRIT=${SWAP_CRIT:-80}
DISK_WARN=${DISK_WARN:-80}; DISK_CRIT=${DISK_CRIT:-90}
LOAD_WARN=${LOAD_WARN:-1.0}; LOAD_CRIT=${LOAD_CRIT:-2.0}   # load per CPU core

QUIET=false
LOG_FILE=""
WEBHOOK=""
WORST=0          # 0 OK, 1 WARN, 2 CRIT
PROBLEMS=()
REPORT=""

usage() { sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; }

while getopts ":ql:w:h" opt; do
  case "$opt" in
    q) QUIET=true ;;
    l) LOG_FILE=$OPTARG ;;
    w) WEBHOOK=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

out() { REPORT+="$*"$'\n'; }

# grade <name> <value> <warn> <crit> <display text>
grade() {
  local name=$1 value=$2 warn=$3 crit=$4 text=$5 level=0 label="OK"
  if awk -v v="$value" -v c="$crit" 'BEGIN {exit !(v >= c)}'; then
    level=2; label="CRIT"
  elif awk -v v="$value" -v w="$warn" 'BEGIN {exit !(v >= w)}'; then
    level=1; label="WARN"
  fi
  (( level > WORST )) && WORST=$level
  (( level > 0 )) && PROBLEMS+=("$label $name: $text")
  out "$(printf '  %-5s %-24s %s' "$label" "$name" "$text")"
}

cpu_usage() {
  # Two samples of /proc/stat one second apart: busy time / total time
  local a b
  read -r -a a < <(grep '^cpu ' /proc/stat)
  sleep 1
  read -r -a b < <(grep '^cpu ' /proc/stat)
  local idle=$(( (b[4] + b[5]) - (a[4] + a[5]) ))
  local total=0 i
  for i in 1 2 3 4 5 6 7 8; do
    total=$(( total + b[i] - a[i] ))
  done
  (( total > 0 )) || { echo 0; return; }
  awk -v i="$idle" -v t="$total" 'BEGIN {printf "%.1f", (t - i) * 100 / t}'
}

# ---------- system info ----------
PRETTY_NAME=$(awk -F= '$1 == "PRETTY_NAME" {gsub(/"/, "", $2); print $2}' /etc/os-release 2>/dev/null || true)
cores=$(nproc)
out "Server health report: $(hostname) - $(date '+%F %T')"
out "  OS: ${PRETTY_NAME:-unknown} | Kernel: $(uname -r) | Uptime: $(uptime -p 2>/dev/null || echo unknown) | CPU cores: $cores"
out ""
out "Checks:"

# ---------- CPU ----------
cpu=$(cpu_usage)
grade "CPU usage" "$cpu" "$CPU_WARN" "$CPU_CRIT" "${cpu}%"

# ---------- load ----------
read -r load1 load5 load15 _ < /proc/loadavg
per_core=$(awk -v l="$load5" -v c="$cores" 'BEGIN {printf "%.2f", l / c}')
grade "Load (5 min)" "$per_core" "$LOAD_WARN" "$LOAD_CRIT" "$load1 / $load5 / $load15 (${per_core} per core)"

# ---------- memory and swap ----------
read -r mem_total mem_avail < <(awk '/^MemTotal/ {t=$2} /^MemAvailable/ {a=$2} END {print t, a}' /proc/meminfo)
mem_pct=$(awk -v t="$mem_total" -v a="$mem_avail" 'BEGIN {printf "%.1f", (t - a) * 100 / t}')
grade "Memory" "$mem_pct" "$MEM_WARN" "$MEM_CRIT" \
  "${mem_pct}% used ($(( (mem_total - mem_avail) / 1024 )) MB of $(( mem_total / 1024 )) MB)"

read -r swap_total swap_free < <(awk '/^SwapTotal/ {t=$2} /^SwapFree/ {f=$2} END {print t, f}' /proc/meminfo)
if (( swap_total > 0 )); then
  swap_pct=$(awk -v t="$swap_total" -v f="$swap_free" 'BEGIN {printf "%.1f", (t - f) * 100 / t}')
  grade "Swap" "$swap_pct" "$SWAP_WARN" "$SWAP_CRIT" "${swap_pct}% used"
else
  out "  INFO  Swap                     not configured"
fi

# ---------- disks ----------
while read -r mount pct; do
  pct=${pct%\%}
  grade "Disk $mount" "$pct" "$DISK_WARN" "$DISK_CRIT" "${pct}% used"
done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | awk 'NR > 1 {print $6, $5}')

# ---------- zombies ----------
zombies=$(ps -eo stat= | grep -c '^Z' || true)
grade "Zombie processes" "$zombies" 1 10 "$zombies"

# ---------- systemd ----------
if [[ -d /run/systemd/system ]]; then
  failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || true)
  failed_count=$(wc -w <<< "$failed_units")
  grade "Failed services" "$failed_count" 1 1 "${failed_count}${failed_units:+ ($failed_units)}"
fi

# ---------- top processes ----------
out ""
out "Top 5 processes by CPU:"
out "$(ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 6 | sed 's/^/  /' || true)"
out ""
out "Top 5 processes by memory:"
out "$(ps -eo pid,user,%cpu,%mem,comm --sort=-%mem | head -n 6 | sed 's/^/  /' || true)"

# ---------- result ----------
status_names=(OK WARNING CRITICAL)
STATUS=${status_names[$WORST]}
out ""
out "Overall status: $STATUS"

[[ "$QUIET" == true ]] || printf '%s' "$REPORT"

summary="$(date '+%F %T') $(hostname) $STATUS cpu=${cpu}% mem=${mem_pct}% load5=${load5}"
if (( ${#PROBLEMS[@]} > 0 )); then
  summary+=" | $(IFS=';'; echo "${PROBLEMS[*]}")"
fi
if [[ -n "$LOG_FILE" ]]; then
  echo "$summary" >> "$LOG_FILE"
fi
[[ "$QUIET" == true ]] && echo "$summary"

if [[ -n "$WEBHOOK" && $WORST -gt 0 ]]; then
  text="Health $STATUS on $(hostname): $(IFS=';'; echo "${PROBLEMS[*]}")"
  text=${text//\\/\\\\}
  text=${text//\"/\\\"}
  curl -fsS -m 10 -X POST -H 'Content-Type: application/json' \
    --data "{\"text\": \"$text\"}" "$WEBHOOK" >/dev/null \
    || echo "Could not send webhook alert" >&2
fi

exit "$WORST"
