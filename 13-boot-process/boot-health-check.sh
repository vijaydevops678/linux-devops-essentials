#!/usr/bin/env bash
#
# boot-health-check.sh - Check how the server booted and whether the next boot is safe.
#
# Reports uptime and reboot history, whether a reboot is pending (kernel or
# library updates), boot time and the slowest services, failed units, errors
# from the previous boot, installed kernels, and validates /etc/fstab. A
# broken fstab line is the most common reason a cloud server never comes
# back after a reboot.
#
# Usage:   sudo ./boot-health-check.sh [-f fstab_file]
# Example: ./boot-health-check.sh -f sample-fstab      (check a practice file)
# Exit code: 0 = no problems, 1 = problems found

set -euo pipefail

FSTAB=/etc/fstab
PROBLEMS=0

usage() {
  cat <<EOF
Usage: ${0##*/} [-f fstab_file]

  -f file  Validate this fstab file instead of /etc/fstab
  -h       Show this help
EOF
}

while getopts ":f:h" opt; do
  case "$opt" in
    f) FSTAB=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

header()  { printf '\n== %s ==\n' "$1"; }
problem() { echo "  PROBLEM: $*"; PROBLEMS=$((PROBLEMS + 1)); }
SYSTEMD=false
[[ -d /run/systemd/system ]] && SYSTEMD=true

echo "Boot health check on $(hostname) at $(date '+%F %T')"

header "Uptime and reboots"
echo "  Up since: $(uptime -s 2>/dev/null || echo unknown) ($(uptime -p 2>/dev/null || echo unknown))"
if command -v last >/dev/null 2>&1; then
  reboots=$(last -x reboot 2>/dev/null | grep '^reboot' | head -n 5 || true)
  if [[ -n "$reboots" ]]; then
    echo "  Last reboots:"
    sed 's/^/    /' <<< "$reboots"
  fi
fi

header "Pending reboot"
if [[ -f /var/run/reboot-required ]]; then
  pkgs=$(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null || true)
  problem "reboot required by package updates ${pkgs:+($pkgs)}"
elif command -v needs-restarting >/dev/null 2>&1; then
  if needs-restarting -r >/dev/null 2>&1; then
    echo "  OK: no reboot needed"
  else
    problem "reboot required (needs-restarting -r)"
  fi
else
  echo "  OK: no reboot-required flag"
fi
running=$(uname -r)
newest=$(find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' 2>/dev/null | sed 's/^vmlinuz-//' | sort -V | tail -n 1 || true)
echo "  Running kernel:        $running"
echo "  Newest kernel in /boot: ${newest:-unknown}"
if [[ -n "$newest" && "$newest" != "$running" ]]; then
  problem "a newer kernel is installed but not running yet (reboot to use it)"
fi

header "Boot time and slowest services"
if [[ "$SYSTEMD" == true ]]; then
  systemd-analyze 2>/dev/null | head -n 1 | sed 's/^/  /' || true
  echo "  Default target: $(systemctl get-default 2>/dev/null || echo unknown)"
  echo "  Slowest units:"
  systemd-analyze blame 2>/dev/null | head -n 8 | sed 's/^/   /' || true
else
  echo "  skipped: systemd is not running"
fi

header "Failed units"
if [[ "$SYSTEMD" == true ]]; then
  failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' || true)
  if [[ -z "$failed" ]]; then
    echo "  OK: none"
  else
    while read -r unit; do problem "$unit failed (see: journalctl -u $unit -b)"; done <<< "$failed"
  fi
else
  echo "  skipped: systemd is not running"
fi

header "Errors from the previous boot"
if command -v journalctl >/dev/null 2>&1 && [[ "$SYSTEMD" == true ]]; then
  prev=$(journalctl -b -1 -p err --no-pager -q 2>/dev/null | tail -n 10 || true)
  if [[ -z "$prev" ]]; then
    echo "  none recorded (or the journal is not persistent: mkdir -p /var/log/journal)"
  else
    sed 's/^/  /' <<< "$prev"
  fi
else
  echo "  skipped: no systemd journal"
fi

header "Installed kernels"
find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '  %f\n' 2>/dev/null | sort -V || true
boot_use=$(df -P /boot 2>/dev/null | awk 'NR == 2 {print $5}' || true)
echo "  /boot usage: ${boot_use:-unknown}"
if [[ "${boot_use%\%}" =~ ^[0-9]+$ ]] && (( ${boot_use%\%} >= 85 )); then
  problem "/boot is ${boot_use} full; kernel updates may fail (remove old kernels: apt autoremove)"
fi

header "fstab check: $FSTAB"
[[ -r "$FSTAB" ]] || { echo "  cannot read $FSTAB"; exit 1; }
line_no=0
while read -r device mountpoint fstype options _; do
  line_no=$((line_no + 1))
  [[ -z "${device:-}" || "$device" == \#* ]] && continue
  if [[ -z "${fstype:-}" ]]; then
    problem "line $line_no: incomplete entry '$device $mountpoint'"
    continue
  fi

  # Does the device exist?
  case "$device" in
    UUID=*|LABEL=*|PARTUUID=*|PARTLABEL=*)
      if command -v findfs >/dev/null 2>&1 && ! findfs "$device" >/dev/null 2>&1; then
        problem "line $line_no: $device not found on this machine"
      fi ;;
    /dev/*)
      [[ -e "$device" ]] || problem "line $line_no: $device does not exist" ;;
  esac

  # Does the mount point exist?
  if [[ "$fstype" != swap && "$mountpoint" == /* && ! -d "$mountpoint" ]]; then
    problem "line $line_no: mount point $mountpoint does not exist (mkdir -p $mountpoint)"
  fi

  # Extra disks without nofail stop the boot if the disk is missing
  case "$mountpoint" in
    /|/boot|/boot/efi|/usr|/var|none|swap) ;;
    *)
      if [[ "$fstype" != swap && "$options" != *nofail* && "$device" != tmpfs ]]; then
        echo "  WARN: line $line_no: $mountpoint has no 'nofail'; if that disk is missing, boot drops to emergency mode"
      fi ;;
  esac
done < "$FSTAB"

if [[ "$FSTAB" == /etc/fstab ]] && command -v findmnt >/dev/null 2>&1; then
  if findmnt --verify >/dev/null 2>&1; then
    echo "  OK: findmnt --verify passed"
  else
    problem "findmnt --verify reported issues:"
    findmnt --verify 2>&1 | sed 's/^/    /' || true
  fi
fi

header "Summary"
if (( PROBLEMS == 0 )); then
  echo "  No problems found. The server should boot cleanly."
  exit 0
fi
echo "  $PROBLEMS problem(s) found. Fix them before the next reboot."
exit 1
