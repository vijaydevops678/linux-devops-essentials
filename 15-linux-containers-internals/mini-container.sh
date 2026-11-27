#!/usr/bin/env bash
#
# mini-container.sh - Build and run a container from scratch, without Docker.
#
# Shows that a container is just a normal Linux process with:
#   - its own root filesystem      (chroot into a folder of copied binaries)
#   - namespaces                    (unshare: own PIDs, hostname, mounts, IPC, network)
#   - cgroup limits                 (memory, CPU and process count via cgroup v2)
#
# Usage:   sudo ./mini-container.sh [-m memory] [-c cpu_percent] [-p max_pids] [-H hostname] [-- command ...]
# Example: sudo ./mini-container.sh                       (interactive shell inside the container)
#          sudo ./mini-container.sh -m 50M -- ps aux      (run one command and exit)
#
# Inside the container try:  ps aux · hostname · cat /proc/self/cgroup · tail /dev/zero (hits the memory limit)

set -euo pipefail

MEMORY=100M
CPU_PERCENT=50
MAX_PIDS=50
CT_HOSTNAME=mini-container
ROOTFS=${ROOTFS:-/tmp/mini-container-rootfs}
CGROUP_ROOT=${CGROUP_ROOT:-/sys/fs/cgroup}
BINARIES=(bash sh ls ps cat hostname id sleep head tail grep cut wc uname mount df free env)
CGROUP=""

usage() { sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; }
log() { echo "[mini-container] $*"; }
die() { echo "[mini-container] ERROR: $*" >&2; exit 1; }

while getopts ":m:c:p:H:h" opt; do
  case "$opt" in
    m) MEMORY=$OPTARG ;;
    c) CPU_PERCENT=$OPTARG ;;
    p) MAX_PIDS=$OPTARG ;;
    H) CT_HOSTNAME=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
[[ "${1:-}" == "--" ]] && shift
if [[ $# -gt 0 ]]; then CMD=("$@"); else CMD=(/bin/bash); fi

[[ $EUID -eq 0 ]] || die "Run as root (namespaces and cgroups need root)"
[[ "$MEMORY" =~ ^[0-9]+[KMG]?$ ]] || die "-m must look like 100M or 1G"
[[ "$CPU_PERCENT" =~ ^[0-9]+$ ]] && (( CPU_PERCENT > 0 )) || die "-c must be a positive number"
[[ "$MAX_PIDS" =~ ^[0-9]+$ ]] || die "-p must be a number"
for tool in unshare chroot ldd; do
  type -P "$tool" >/dev/null 2>&1 || die "$tool is required"
done
UNSHARE=$(type -P unshare)
CHROOT=$(type -P chroot)

cleanup() {
  if [[ -n "$CGROUP" && -d "$CGROUP" ]]; then
    rmdir "$CGROUP" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---------- 1. root filesystem ----------
# Copy each program and the shared libraries it needs (found with ldd).
build_rootfs() {
  log "Building root filesystem in $ROOTFS"
  mkdir -p "$ROOTFS"/{bin,proc,dev,tmp,etc,root}
  chmod 1777 "$ROOTFS/tmp"
  local bin path lib
  for bin in "${BINARIES[@]}"; do
    path=$(type -P "$bin") || continue   # type -P: the program file, never a shell builtin
    cp -L "$path" "$ROOTFS/bin/$bin"
    while read -r lib; do
      [[ -n "$lib" && -e "$lib" ]] && cp -L --parents "$lib" "$ROOTFS/"
    done < <(ldd "$path" 2>/dev/null | grep -o '/[^ ]*' || true)
  done
  echo "root:x:0:0:root:/root:/bin/bash" > "$ROOTFS/etc/passwd"
  echo "root:x:0:" > "$ROOTFS/etc/group"
  [[ -e "$ROOTFS/dev/null" ]] || mknod -m 666 "$ROOTFS/dev/null" c 1 3
  [[ -e "$ROOTFS/dev/zero" ]] || mknod -m 666 "$ROOTFS/dev/zero" c 1 5
  touch "$ROOTFS/.complete"
  log "Root filesystem ready: $(du -sh "$ROOTFS" | cut -f1), $(find "$ROOTFS/bin" -type f | wc -l) programs"
}
if [[ ! -f "$ROOTFS/.complete" ]]; then
  build_rootfs
else
  log "Reusing root filesystem in $ROOTFS (delete it to rebuild)"
fi

# ---------- 2. cgroup limits ----------
if [[ -f "$CGROUP_ROOT/cgroup.controllers" ]]; then
  CGROUP="$CGROUP_ROOT/mini-container-$$"
  available=$(cat "$CGROUP_ROOT/cgroup.controllers")
  for c in memory cpu pids; do
    if [[ " $available " == *" $c "* ]]; then
      echo "+$c" > "$CGROUP_ROOT/cgroup.subtree_control" 2>/dev/null || true
    fi
  done
  mkdir -p "$CGROUP"
  if [[ -f "$CGROUP/memory.max" ]]; then
    echo "$MEMORY" > "$CGROUP/memory.max"
    [[ -f "$CGROUP/memory.swap.max" ]] && echo 0 > "$CGROUP/memory.swap.max"
    log "cgroup: memory limited to $MEMORY (memory.max)"
  else
    log "cgroup: memory controller not available, no memory limit"
  fi
  if [[ -f "$CGROUP/cpu.max" ]]; then
    echo "$(( CPU_PERCENT * 1000 )) 100000" > "$CGROUP/cpu.max"
    log "cgroup: CPU limited to ${CPU_PERCENT}% of one core (cpu.max)"
  else
    log "cgroup: cpu controller not available, no CPU limit"
  fi
  if [[ -f "$CGROUP/pids.max" ]]; then
    echo "$MAX_PIDS" > "$CGROUP/pids.max"
    log "cgroup: at most $MAX_PIDS processes (pids.max)"
  else
    log "cgroup: pids controller not available, no process limit"
  fi
else
  log "cgroup v2 not found at $CGROUP_ROOT: running without resource limits"
fi

# ---------- 3. namespaces + chroot ----------
log "Namespaces: pid (own process tree), uts (own hostname), mnt (own mounts), ipc, net (no network)"
log "Starting '${CMD[*]}' as hostname '$CT_HOSTNAME'"
echo

set +e
(
  # Move this subshell into the cgroup; everything it starts inherits the limits
  if [[ -n "$CGROUP" ]]; then
    echo "$BASHPID" > "$CGROUP/cgroup.procs"
  fi
  exec env -i PATH=/bin HOME=/root TERM="${TERM:-xterm}" PS1="[\\u@\\h \\w]# " \
    "$UNSHARE" --pid --fork --uts --ipc --net --mount --mount-proc="$ROOTFS/proc" \
    "$CHROOT" "$ROOTFS" /bin/bash -c 'hostname "$1"; shift; exec "$@"' _ "$CT_HOSTNAME" "${CMD[@]}"
)
status=$?
set -e

echo
if (( status == 137 )); then
  log "Container was killed (exit 137): it most likely hit the memory limit and the OOM killer stopped it"
else
  log "Container exited with code $status"
fi
exit "$status"
