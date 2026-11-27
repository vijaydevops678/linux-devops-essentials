#!/usr/bin/env bash
#
# perf-snapshot.sh - "Why is the server slow right now?" in one command.
#
# Samples the kernel counters in /proc twice, a few seconds apart, and shows
# CPU time split (user, system, iowait, steal), run queue, memory and swap
# activity, disk throughput and busy %, network throughput, the top
# processes, processes stuck waiting on IO, and recent OOM kills. It ends
# with a plain-language verdict. Needs no extra tools: only /proc.
#
# Usage:   ./perf-snapshot.sh [-i seconds]
# Example: ./perf-snapshot.sh -i 10

set -euo pipefail

INTERVAL=5

usage() {
  cat <<EOF
Usage: ${0##*/} [-i seconds]

  -i seconds  Sampling interval (default: $INTERVAL)
  -h          Show this help
EOF
}

while getopts ":i:h" opt; do
  case "$opt" in
    i) INTERVAL=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
[[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]] || { echo "-i must be a whole number of seconds" >&2; exit 1; }

header() { printf '\n== %s ==\n' "$1"; }
VERDICT=()
flag() { VERDICT+=("$*"); }
gt() { awk -v a="$1" -v b="$2" 'BEGIN {exit !(a > b)}'; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

snapshot() {
  local n=$1
  cat /proc/stat     > "$TMP/stat.$n"
  cat /proc/vmstat   > "$TMP/vmstat.$n"
  cat /proc/diskstats > "$TMP/disk.$n"
  cat /proc/net/dev  > "$TMP/net.$n"
}

echo "Performance snapshot of $(hostname) at $(date '+%F %T'), sampling for ${INTERVAL}s..."
snapshot 1
sleep "$INTERVAL"
snapshot 2

cores=$(nproc)

# ---------- CPU ----------
header "CPU (${cores} cores)"
read -r user nice system idle iowait irq softirq steal < <(
  awk 'FNR == 1 && $1 == "cpu" {for (i = 2; i <= 9; i++) v[FILENAME, i] = $i}
       END {
         for (i = 2; i <= 9; i++) {
           d[i] = v[ARGV[2], i] - v[ARGV[1], i]; t += d[i]
         }
         if (t == 0) t = 1
         for (i = 2; i <= 9; i++) printf "%.1f ", d[i] * 100 / t
         print ""
       }' "$TMP/stat.1" "$TMP/stat.2")
printf '  user %5s%%  system %5s%%  iowait %5s%%  steal %5s%%  idle %5s%%  (nice %s%%, irq %s%%, softirq %s%%)\n' \
  "$user" "$system" "$iowait" "$steal" "$idle" "$nice" "$irq" "$softirq"

read -r running blocked < <(awk '/^procs_running/ {r = $2} /^procs_blocked/ {b = $2} END {print r, b}' "$TMP/stat.2")
read -r load1 load5 _ < /proc/loadavg
echo "  Run queue: $running running, $blocked blocked on IO | load 1m $load1, 5m $load5"

busy=$(awk -v i="$idle" 'BEGIN {printf "%.1f", 100 - i}')
gt "$busy" 90 && flag "CPU is saturated (${busy}% busy). Find the process below; consider more CPU or optimising it."
gt "$iowait" 20 && flag "High iowait (${iowait}%): the CPU is waiting for the disk. Check the disk table below."
gt "$steal" 10 && flag "High steal time (${steal}%): the hypervisor is giving your CPU to other VMs. Resize or move the instance."
gt "$running" $(( cores * 2 )) && flag "Run queue ($running) is more than twice the core count: processes are waiting for CPU."

# ---------- memory ----------
header "Memory"
awk '/^MemTotal/ {t = $2} /^MemAvailable/ {a = $2} /^Cached/ {c = $2} /^SwapTotal/ {st = $2} /^SwapFree/ {sf = $2}
     END {
       printf "  Total %d MB | used %d MB (%.0f%%) | available %d MB | page cache %d MB\n", t/1024, (t-a)/1024, (t-a)*100/t, a/1024, c/1024
       if (st > 0) printf "  Swap %d MB, used %d MB\n", st/1024, (st-sf)/1024; else print "  Swap: not configured"
     }' /proc/meminfo
read -r swap_in swap_out < <(awk '$1 == "pswpin" {i[FILENAME] = $2} $1 == "pswpout" {o[FILENAME] = $2}
  END {printf "%d %d\n", i[ARGV[2]] - i[ARGV[1]], o[ARGV[2]] - o[ARGV[1]]}' "$TMP/vmstat.1" "$TMP/vmstat.2")
echo "  Swap activity during sample: $swap_in pages in, $swap_out pages out"
avail_pct=$(awk '/^MemTotal/ {t = $2} /^MemAvailable/ {a = $2} END {printf "%.0f", a * 100 / t}' /proc/meminfo)
(( swap_in + swap_out > 100 )) && flag "The system is actively swapping: memory pressure. Find the memory hog below or add RAM."
(( avail_pct < 10 )) && flag "Only ${avail_pct}% memory available: risk of the OOM killer stopping processes."

# ---------- disks ----------
header "Disk IO (per second)"
printf '  %-10s %8s %8s %10s %10s %6s\n' DEVICE READS WRITES READ_KB WRITE_KB BUSY%
awk -v secs="$INTERVAL" -v busyfile="$TMP/busy" '
  $3 !~ /^(loop|ram|sr|fd)/ && $3 !~ /[0-9]p[0-9]+$/ && $3 !~ /^(sd|vd|xvd|hd)[a-z]+[0-9]+$/ {
    key = $3
    if (FILENAME == ARGV[1]) {r[key] = $4; rs[key] = $6; w[key] = $8; ws[key] = $10; io[key] = $13}
    else if (key in r) {
      busy = ($13 - io[key]) / (secs * 10); if (busy > 100) busy = 100
      printf "  %-10s %8.1f %8.1f %10.1f %10.1f %5.0f%%\n", key, ($4 - r[key]) / secs, ($8 - w[key]) / secs,
             ($6 - rs[key]) / 2 / secs, ($10 - ws[key]) / 2 / secs, busy
      if (busy > 80) print key > busyfile
    }
  }' "$TMP/disk.1" "$TMP/disk.2"
if [[ -s "$TMP/busy" ]]; then
  flag "Disk $(tr '\n' ' ' < "$TMP/busy")is over 80% busy: an IO bottleneck. Check the processes in D state below."
fi

# ---------- network ----------
header "Network (per second)"
printf '  %-12s %12s %12s\n' INTERFACE RX_KB TX_KB
awk -v secs="$INTERVAL" '
  FNR > 2 {
    line = $0
    sub(/^ +/, "", line)
    split(line, f, /[: ]+/)
    dev = f[1]
    if (dev == "lo") next
    if (FILENAME == ARGV[1]) {rx[dev] = f[2]; tx[dev] = f[10]}
    else if (dev in rx) printf "  %-12s %12.1f %12.1f\n", dev, (f[2] - rx[dev]) / 1024 / secs, (f[10] - tx[dev]) / 1024 / secs
  }' "$TMP/net.1" "$TMP/net.2"

# ---------- processes ----------
header "Top 5 processes by CPU"
ps -eo pid,user,%cpu,%mem,stat,comm --sort=-%cpu | head -n 6 | sed 's/^/  /' || true

header "Top 5 processes by memory (RSS)"
ps -eo pid,user,rss,%mem,comm --sort=-rss | head -n 6 | sed 's/^/  /' || true

header "Processes waiting on IO (state D)"
dstate=$(ps -eo pid,stat,wchan:20,comm --no-headers | awk '$2 ~ /^D/' || true)
if [[ -z "$dstate" ]]; then echo "  none"; else sed 's/^/  /' <<< "$dstate"; fi

header "Recent OOM kills"
oom=""
if command -v journalctl >/dev/null 2>&1; then
  oom=$(journalctl -k --since "24 hours ago" --no-pager -q 2>/dev/null | grep -iE 'out of memory|oom-kill|killed process' | tail -n 5 || true)
fi
if [[ -z "$oom" ]]; then
  oom=$(dmesg -T 2>/dev/null | grep -iE 'out of memory|oom-kill|killed process' | tail -n 5 || true)
fi
if [[ -z "$oom" ]]; then
  echo "  none found"
else
  sed 's/^/  /' <<< "$oom"
  flag "The OOM killer has stopped processes recently. Check memory limits and leaks."
fi

# ---------- verdict ----------
header "Verdict"
if (( ${#VERDICT[@]} == 0 )); then
  echo "  No bottleneck found in this sample. If users still see slowness, check the application, database and network latency."
else
  for v in "${VERDICT[@]}"; do echo "  - $v"; done
fi
