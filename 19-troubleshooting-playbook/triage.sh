#!/usr/bin/env bash
#
# triage.sh - The first minute on a broken server: collect everything, flag what's wrong.
#
# Runs read-only checks (system, load, memory, disks, failed services, recent
# errors, kernel messages, network, logins, time sync) and saves a full
# report to a file you can attach to the incident ticket. Prints the red
# flags it found, each with the playbook section to read next.
#
# Usage:   sudo ./triage.sh [-o output_dir]
# Example: sudo ./triage.sh -o /tmp
# Exit code: 0 = no red flags, 1 = red flags found

set -uo pipefail     # no -e: one failing check must not stop the others

OUT_DIR=/tmp
FLAGS=()

usage() { sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'; }

while getopts ":o:h" opt; do
  case "$opt" in
    o) OUT_DIR=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

mkdir -p "$OUT_DIR" || exit 1
REPORT="$OUT_DIR/triage-$(hostname)-$(date +%Y%m%d-%H%M%S).txt"
flag() { FLAGS+=("$*"); }
has()  { command -v "$1" >/dev/null 2>&1; }
SYSTEMD=false
[[ -d /run/systemd/system ]] && SYSTEMD=true

# section <title> <command...> : run a command with a time limit and record its output
section() {
  local title=$1
  shift
  {
    printf '\n===== %s =====\n' "$title"
    timeout 15 "$@" 2>&1 || true
  } >> "$REPORT"
}

echo "Triage of $(hostname): collecting..." >&2
{
  echo "Triage report: $(hostname)"
  echo "Generated:     $(date '+%F %T %Z') by $(id -un)"
} > "$REPORT"

# ---------- collect ----------
section "System"           bash -c 'grep PRETTY_NAME /etc/os-release; uname -a; echo "Uptime: $(uptime -p) (since $(uptime -s))"'
section "Load and CPU"     bash -c 'cat /proc/loadavg; echo "Cores: $(nproc)"; top -bn1 | head -n 15'
section "Memory"           free -h
section "Disk space"       df -hT -x tmpfs -x devtmpfs -x squashfs
section "Inodes"           df -i -x tmpfs -x devtmpfs -x squashfs
section "Top CPU"          bash -c 'ps -eo pid,user,%cpu,%mem,etime,comm --sort=-%cpu | head -n 11'
section "Top memory"       bash -c 'ps -eo pid,user,rss,%mem,comm --sort=-rss | head -n 11'
if [[ "$SYSTEMD" == true ]]; then
  section "Failed services"            systemctl --failed --no-pager
  section "Errors in the last hour"    journalctl -p err --since "1 hour ago" --no-pager -q -n 50
  section "Time sync"                  timedatectl
fi
section "Kernel messages (last 30)" bash -c 'dmesg -T 2>/dev/null | tail -n 30 || journalctl -k -n 30 --no-pager'
if has ss; then section "Listening ports" ss -tulpn; fi
if has ss; then section "Connection summary" ss -s; fi
section "DNS"              bash -c 'grep -E "^(nameserver|search)" /etc/resolv.conf; getent hosts github.com || echo "github.com does not resolve"'
section "Recent logins"    bash -c 'last -n 10 2>/dev/null || true'
section "Recent reboots"   bash -c 'last -x reboot -n 5 2>/dev/null || true'

# ---------- red flags ----------
while read -r mount pct; do
  pct=${pct%\%}
  [[ "$pct" =~ ^[0-9]+$ ]] && (( pct >= 90 )) && flag "Disk $mount is ${pct}% full -> playbook: 1. Disk full"
done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR > 1 {print $6, $5}')

while read -r mount pct; do
  pct=${pct%\%}
  [[ "$pct" =~ ^[0-9]+$ ]] && (( pct >= 90 )) && flag "Inodes on $mount ${pct}% used -> playbook: 1. Disk full"
done < <(df -Pi -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR > 1 {print $6, $5}')

avail_pct=$(awk '/^MemTotal/ {t = $2} /^MemAvailable/ {a = $2} END {printf "%d", a * 100 / t}' /proc/meminfo)
(( avail_pct < 10 )) && flag "Only ${avail_pct}% memory available -> playbook: 3. Out of memory"

read -r load1 _ < /proc/loadavg
if awk -v l="$load1" -v c="$(nproc)" 'BEGIN {exit !(l > 2 * c)}'; then
  flag "Load $load1 is more than twice the $(nproc) cores -> playbook: 2. Server slow / high CPU"
fi

kernel_log=$(dmesg -T 2>/dev/null || journalctl -k --since "24 hours ago" --no-pager -q 2>/dev/null || true)
grep -qiE 'out of memory|oom-kill|killed process' <<< "$kernel_log" \
  && flag "The OOM killer stopped processes -> playbook: 3. Out of memory"
grep -qiE 'I/O error|EXT4-fs error|XFS .* error|blk_update_request' <<< "$kernel_log" \
  && flag "Disk I/O errors in kernel messages: the disk may be failing -> check dmesg, cloud volume status"

if [[ "$SYSTEMD" == true ]]; then
  failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
  [[ -n "${failed// /}" ]] && flag "Failed services: $failed-> playbook: 5. Service won't start"
  synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)
  [[ "$synced" == no ]] && flag "Clock is not NTP-synchronised -> playbook: 9. Clock wrong"
fi

zombies=$(ps -eo stat= | grep -c '^Z')
(( zombies > 10 )) && flag "$zombies zombie processes: a parent process is not reaping its children"

getent hosts github.com >/dev/null 2>&1 || flag "DNS lookup of github.com failed -> playbook: 7. DNS not resolving"

[[ -f /var/run/reboot-required ]] && flag "A reboot is pending after updates (plan one)"

# ---------- summary ----------
{
  printf '\n===== RED FLAGS =====\n'
  if (( ${#FLAGS[@]} == 0 )); then echo "none"; else printf -- '- %s\n' "${FLAGS[@]}"; fi
} >> "$REPORT"

echo "Report saved: $REPORT ($(wc -l < "$REPORT") lines). Attach it to the incident ticket."
echo
if (( ${#FLAGS[@]} == 0 )); then
  echo "No red flags. If users still see problems, check the application logs and dependencies (database, APIs)."
  exit 0
fi
echo "RED FLAGS:"
printf '  - %s\n' "${FLAGS[@]}"
exit 1
