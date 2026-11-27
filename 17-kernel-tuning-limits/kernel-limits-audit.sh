#!/usr/bin/env bash
#
# kernel-limits-audit.sh - Check kernel settings and limits that break servers under load.
#
# Reviews the sysctl values that matter for web servers, databases and
# containers, system-wide file handle usage, the processes closest to their
# open-file limit ("Too many open files"), and with -k the kernel
# prerequisites of a Kubernetes node.
#
# Usage:   sudo ./kernel-limits-audit.sh [-k]
# Example: sudo ./kernel-limits-audit.sh -k
# Exit code: 0 = no warnings, 1 = warnings found

set -euo pipefail

K8S=false
WARNINGS=0

usage() { sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'; }

while getopts ":kh" opt; do
  case "$opt" in
    k) K8S=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

header() { printf '\n== %s ==\n' "$1"; }
row()    { printf '  %-5s %-36s %-14s %s\n' "$1" "$2" "$3" "$4"; }
warn()   { row WARN "$1" "$2" "$3"; WARNINGS=$((WARNINGS + 1)); }

# Reads a sysctl value straight from /proc/sys (works without the sysctl binary)
sysval() {
  local f="/proc/sys/${1//./\/}"
  if [[ -r "$f" ]]; then tr -s '\t ' ' ' < "$f"; else echo "n/a"; fi
}

# check_min <key> <minimum> <level WARN|INFO> <why>
check_min() {
  local key=$1 min=$2 level=$3 why=$4 value
  value=$(sysval "$key")
  if [[ "$value" == "n/a" ]]; then
    row INFO "$key" "n/a" "not available on this kernel"
  elif (( value >= min )); then
    row OK "$key" "$value" ""
  elif [[ "$level" == WARN ]]; then
    warn "$key" "$value" "recommended >= $min: $why"
  else
    row INFO "$key" "$value" "set >= $min if needed: $why"
  fi
}

echo "Kernel and limits audit on $(hostname) at $(date '+%F %T')"
echo "Kernel: $(uname -r)   Command line: $(cut -c1-80 /proc/cmdline)"

header "sysctl settings"
row "" SETTING VALUE NOTE
check_min fs.file-max 100000 WARN "system-wide open files"
check_min fs.inotify.max_user_watches 524288 INFO "file watchers: IDEs, webpack, kubelet, log shippers"
check_min fs.inotify.max_user_instances 512 INFO "many containers or watchers per user"
check_min net.core.somaxconn 4096 WARN "listen backlog for busy web servers"
check_min net.ipv4.tcp_max_syn_backlog 4096 INFO "half-open connections during traffic spikes"
check_min vm.max_map_count 262144 INFO "required by Elasticsearch / OpenSearch"

range=$(sysval net.ipv4.ip_local_port_range)
if [[ "$range" =~ ^([0-9]+)\ ([0-9]+)$ ]] && (( BASH_REMATCH[2] - BASH_REMATCH[1] < 28000 )); then
  warn net.ipv4.ip_local_port_range "$range" "small range: proxies making many outgoing connections run out of ports"
else
  row OK net.ipv4.ip_local_port_range "$range" ""
fi

swappiness=$(sysval vm.swappiness)
row INFO vm.swappiness "$swappiness" "default 60; databases often use 1-10"
row INFO net.ipv4.ip_forward "$(sysval net.ipv4.ip_forward)" "must be 1 for Docker/Kubernetes routing"

header "System-wide file handles"
read -r allocated _ max < /proc/sys/fs/file-nr
pct=$(awk -v a="$allocated" -v m="$max" 'BEGIN {printf "%.2f", a * 100 / m}')
echo "  $allocated in use of $max ($pct%)"
if awk -v p="$pct" 'BEGIN {exit !(p > 80)}'; then
  warn "fs.file-nr" "$pct%" "more than 80% of all file handles are in use"
fi

header "Open-file limits"
echo "  This shell: soft $(ulimit -Sn), hard $(ulimit -Hn)"
if [[ -d /run/systemd/system ]]; then
  echo "  systemd default for services: $(systemctl show -p DefaultLimitNOFILE --value 2>/dev/null || echo unknown)"
fi
echo "  Processes closest to their limit:"
printf '    %-7s %-18s %8s %8s %6s\n' PID COMMAND OPEN LIMIT USED
shopt -s nullglob
results=""
for dir in /proc/[0-9]*; do
  pid=${dir#/proc/}
  fds=("$dir"/fd/*)
  (( ${#fds[@]} > 0 )) || continue
  limit=$(awk '/^Max open files/ {print $4}' "$dir/limits" 2>/dev/null || true)
  [[ "$limit" =~ ^[0-9]+$ ]] || continue
  comm=$(cat "$dir/comm" 2>/dev/null || echo "?")
  results+="$pid ${comm// /_} ${#fds[@]} $limit"$'\n'
done
shopt -u nullglob
top=$(awk 'NF == 4 {printf "%s %s %s %s %.1f\n", $1, $2, $3, $4, $3 * 100 / $4}' <<< "$results" | sort -k5 -rn | head -n 5 || true)
while read -r pid comm open limit used; do
  [[ -n "${pid:-}" ]] || continue
  printf '    %-7s %-18s %8s %8s %5s%%\n' "$pid" "${comm:0:18}" "$open" "$limit" "$used"
  if awk -v u="$used" 'BEGIN {exit !(u > 80)}'; then
    warn "open files: $comm ($pid)" "$used%" "close to 'Too many open files'; raise LimitNOFILE for its service"
  fi
done <<< "$top"
[[ $EUID -eq 0 ]] || echo "    (run as root to see every process)"

header "Kernel modules"
if [[ -r /proc/modules ]]; then
  echo "  $(wc -l < /proc/modules) modules loaded (lsmod for the list)"
else
  echo "  module list not available (kernel without loadable modules, or a container)"
fi

if [[ "$K8S" == true ]]; then
  header "Kubernetes node prerequisites"
  # Built-in modules may not appear in /sys/module, so also check what they provide
  if [[ -d /sys/module/overlay ]] || grep -qw overlay /proc/filesystems; then
    row OK "module overlay" loaded ""
  else
    warn "module overlay" missing "sudo modprobe overlay; add it to /etc/modules-load.d/k8s.conf"
  fi
  if [[ -d /sys/module/br_netfilter || -d /proc/sys/net/bridge ]]; then
    row OK "module br_netfilter" loaded ""
  else
    warn "module br_netfilter" missing "sudo modprobe br_netfilter; add it to /etc/modules-load.d/k8s.conf"
  fi
  for key in net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward; do
    v=$(sysval "$key")
    if [[ "$v" == 1 ]]; then row OK "$key" "$v" ""; else warn "$key" "$v" "must be 1 (see 99-devops.conf)"; fi
  done
  if (( $(wc -l < /proc/swaps) > 1 )); then
    warn swap "on" "kubelet expects swap off by default: sudo swapoff -a and remove swap from /etc/fstab"
  else
    row OK swap off ""
  fi
  if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    row OK "cgroup v2" enabled ""
  else
    warn "cgroup v2" "not mounted" "current Kubernetes versions expect cgroup v2"
  fi
fi

header "Summary"
if (( WARNINGS == 0 )); then
  echo "  No warnings."
  exit 0
fi
echo "  $WARNINGS warning(s). Persistent fixes go in /etc/sysctl.d/99-devops.conf (then: sudo sysctl --system)."
exit 1
