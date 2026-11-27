#!/usr/bin/env bash
#
# inspect-namespaces.sh - See exactly how a process or container is isolated.
#
# For any PID (or a Docker container name) shows which namespaces it shares
# with the host and which are its own, its cgroup and resource limits, its
# root filesystem, hostname, network interfaces, capabilities and seccomp
# status. This is what `docker run` sets up for you.
#
# Usage:   sudo ./inspect-namespaces.sh <PID | docker_container_name> [reference_PID]
# Example: sudo ./inspect-namespaces.sh 1234
#          sudo ./inspect-namespaces.sh my-nginx
# The reference process (default: PID 1) stands for "the host".

set -euo pipefail

usage() { sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; }

TARGET=${1:-}
REF=${2:-1}
[[ -n "$TARGET" && "$TARGET" != "-h" ]] || { usage; exit 0; }

if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  PID=$TARGET
elif command -v docker >/dev/null 2>&1; then
  PID=$(docker inspect -f '{{.State.Pid}}' "$TARGET" 2>/dev/null) || { echo "No container named $TARGET" >&2; exit 1; }
else
  echo "Give a PID (docker is not installed to look up container names)" >&2
  exit 1
fi

[[ -d "/proc/$PID" ]] || { echo "No process with PID $PID" >&2; exit 1; }
[[ $EUID -eq 0 ]] || echo "Note: run as root to see everything." >&2

header() { printf '\n== %s ==\n' "$1"; }

echo "Process $PID: $(ps -o user=,args= -p "$PID" 2>/dev/null | cut -c1-100)"

[[ -d "/proc/$REF" ]] || { echo "No reference process with PID $REF" >&2; exit 1; }

header "Namespaces (compared with PID $REF, the host)"
printf '  %-8s %-22s %s\n' TYPE ID STATUS
for ns in pid net mnt uts ipc user cgroup time; do
  [[ -e "/proc/$PID/ns/$ns" ]] || continue
  mine=$(readlink "/proc/$PID/ns/$ns" 2>/dev/null || echo "?")
  host=$(readlink "/proc/$REF/ns/$ns" 2>/dev/null || echo "?")
  if [[ "$mine" == "?" ]]; then
    status="unknown (need root)"
  elif [[ "$host" == "?" ]]; then
    status="unknown (cannot read PID $REF; pass another host PID as 2nd argument)"
  elif [[ "$mine" == "$host" ]]; then
    status="shared with host"
  else
    status="ISOLATED"
  fi
  printf '  %-8s %-22s %s\n' "$ns" "${mine#*:}" "$status"
done

pidns=$(readlink "/proc/$PID/ns/pid" 2>/dev/null || true)
if [[ -n "$pidns" ]]; then
  count=0
  for p in /proc/[0-9]*; do
    [[ "$(readlink "$p/ns/pid" 2>/dev/null || true)" == "$pidns" ]] && count=$((count + 1))
  done
  echo "  Processes in the same PID namespace: $count"
fi

header "Hostname and network"
if command -v nsenter >/dev/null 2>&1 && [[ $EUID -eq 0 ]]; then
  echo "  Hostname inside: $(nsenter -t "$PID" -u hostname 2>/dev/null || echo unknown)"
fi
ifaces=$(awk -F: 'NR > 2 {gsub(/ /, "", $1); printf "%s ", $1}' "/proc/$PID/net/dev" 2>/dev/null || true)
echo "  Network interfaces: ${ifaces:-unknown}"
[[ "$ifaces" == "lo " ]] && echo "  (only loopback: this process has no network access)"

header "Root filesystem"
root=$(readlink "/proc/$PID/root" 2>/dev/null || echo unknown)
if [[ "$root" == "/" ]]; then
  echo "  / (same as host, or a mount namespace with its own root, e.g. Docker overlay)"
else
  echo "  $root (chroot)"
fi
if grep -q ' / overlay ' "/proc/$PID/mounts" 2>/dev/null; then
  echo "  Root is an overlay filesystem (container image layers):"
  grep ' / overlay ' "/proc/$PID/mounts" | tr ',' '\n' | grep -E 'lowerdir|upperdir' | cut -c1-120 | sed 's/^/    /' || true
fi

header "cgroup and resource limits"
cg=$(awk -F: '$1 == "0" {print $3}' "/proc/$PID/cgroup" 2>/dev/null || true)
if [[ -n "$cg" && -d "/sys/fs/cgroup$cg" ]]; then
  dir="/sys/fs/cgroup$cg"
  echo "  cgroup: $cg"
  for f in memory.max memory.current cpu.max pids.max pids.current; do
    [[ -r "$dir/$f" ]] && printf '  %-15s %s\n' "$f" "$(cat "$dir/$f")"
  done
  echo "  ('max' means no limit; cpu.max '50000 100000' = 50% of one core)"
else
  echo "  cgroup: ${cg:-unknown} (cgroup v2 not mounted at /sys/fs/cgroup)"
fi

header "Security"
capeff=$(awk '/^CapEff/ {print $2}' "/proc/$PID/status" 2>/dev/null || true)
seccomp=$(awk '/^Seccomp:/ {print $2}' "/proc/$PID/status" 2>/dev/null || true)
echo "  Effective capabilities: ${capeff:-unknown}"
if [[ -n "$capeff" ]] && command -v capsh >/dev/null 2>&1; then
  capsh --decode="$capeff" 2>/dev/null | sed 's/^/    /' | cut -c1-140 || true
fi
case "$seccomp" in
  0) echo "  Seccomp: off (all system calls allowed)" ;;
  1) echo "  Seccomp: strict mode" ;;
  2) echo "  Seccomp: filter active (Docker's default profile blocks ~40 risky system calls)" ;;
  *) echo "  Seccomp: unknown" ;;
esac
