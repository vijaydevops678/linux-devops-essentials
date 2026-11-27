#!/usr/bin/env bash
#
# permission-audit.sh - Audit a Linux system for risky file permissions.
#
# Checks:
#   1. Permissions and owner of critical system files (/etc/shadow, /etc/sudoers, ...)
#   2. World-writable files (anyone on the system can change them)
#   3. World-writable directories without the sticky bit
#   4. Files with no valid owner or group (left behind by deleted users)
#   5. SUID/SGID programs (run with their owner's rights, worth reviewing)
#
# Usage:   sudo ./permission-audit.sh [path]      (default path: /)
# Exit code: 0 = no issues, 1 = issues found

set -euo pipefail

TARGET=${1:-/}
LIMIT=20
ISSUES=0

[[ "${1:-}" == "-h" ]] && { sed -n '3,15p' "$0"; exit 0; }
[[ -d "$TARGET" ]] || { echo "Not a directory: $TARGET" >&2; exit 1; }
[[ $EUID -eq 0 ]] || echo "Note: not running as root, some files cannot be checked." >&2

header() { printf '\n== %s ==\n' "$1"; }

# check_file <path> <most permissive allowed mode, octal>
check_file() {
  local file=$1 allowed=$2 mode owner
  [[ -e "$file" ]] || return 0
  mode=$(stat -c '%a' "$file")
  owner=$(stat -c '%U' "$file")
  if (( (8#$mode & ~8#$allowed) != 0 )); then
    printf '  FAIL  %-22s mode %-4s (should be %s or stricter)\n' "$file" "$mode" "$allowed"
    ISSUES=$((ISSUES + 1))
  elif [[ "$owner" != "root" ]]; then
    printf '  FAIL  %-22s owner %s (should be root)\n' "$file" "$owner"
    ISSUES=$((ISSUES + 1))
  else
    printf '  OK    %-22s mode %s\n' "$file" "$mode"
  fi
}

# list_results <issue|review> <title> <find arguments...>
list_results() {
  local kind=$1 title=$2 results count
  shift 2
  header "$title"
  results=$(find "$@" 2>/dev/null | head -n 1000 || true)
  if [[ -z "$results" ]]; then
    echo "  OK: none found"
    return 0
  fi
  count=$(wc -l <<< "$results")
  echo "  Found $count (showing up to $LIMIT):"
  head -n "$LIMIT" <<< "$results" | sed 's/^/    /'
  if [[ "$kind" == "issue" ]]; then
    ISSUES=$((ISSUES + count))
  fi
}

echo "Permission audit of $TARGET on $(hostname) at $(date '+%F %T')"

header "Critical system files"
check_file /etc/passwd 644
check_file /etc/group 644
check_file /etc/shadow 640
check_file /etc/gshadow 640
check_file /etc/sudoers 440
check_file /etc/ssh/sshd_config 644
check_file /etc/crontab 644
check_file /root 700

list_results issue "World-writable files" \
  "$TARGET" -xdev -type f -perm -0002 -printf '%m %u %p\n'

list_results issue "World-writable directories without sticky bit" \
  "$TARGET" -xdev -type d -perm -0002 ! -perm -1000 -printf '%m %u %p\n'

list_results issue "Files with no valid owner or group" \
  "$TARGET" -xdev \( -nouser -o -nogroup \) -printf '%m %u:%g %p\n'

list_results review "SUID/SGID programs (review that each one is expected)" \
  "$TARGET" -xdev -type f \( -perm -4000 -o -perm -2000 \) -printf '%m %u %p\n'

header "Summary"
if (( ISSUES == 0 )); then
  echo "  No permission issues found."
  exit 0
fi
echo "  $ISSUES issue(s) found. Typical fixes:"
echo "    chmod o-w <file>          remove write access for others"
echo "    chmod +t <dir>            add the sticky bit to a shared directory"
echo "    chown root:root <file>    give an orphaned file a valid owner"
exit 1
