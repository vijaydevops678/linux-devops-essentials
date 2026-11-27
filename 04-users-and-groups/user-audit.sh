#!/usr/bin/env bash
#
# user-audit.sh - Security review of user accounts on a Linux server.
#
# Reports:
#   - human login accounts (UID >= UID_MIN with a real shell)
#   - extra accounts with UID 0 (full root rights)
#   - members of admin groups (sudo, wheel, admin)
#   - accounts with an empty password and locked accounts (needs root)
#   - last login time of each human account
#
# Usage:   sudo ./user-audit.sh
# Exit code: 0 = no critical findings, 1 = critical findings

set -euo pipefail

CRITICAL=0
UID_MIN=$(awk '/^UID_MIN/ {print $2}' /etc/login.defs 2>/dev/null || true)
UID_MIN=${UID_MIN:-1000}

[[ "${1:-}" == "-h" ]] && { sed -n '3,14p' "$0"; exit 0; }

header() { printf '\n== %s ==\n' "$1"; }

echo "User audit on $(hostname) at $(date '+%F %T')"

header "Human login accounts (UID >= $UID_MIN)"
humans=$(awk -F: -v min="$UID_MIN" '$3 >= min && $3 != 65534 && $7 !~ /(nologin|false)$/ {print $1}' /etc/passwd)
if [[ -z "$humans" ]]; then
  echo "  none"
else
  printf '  %-16s %-6s %-22s %s\n' USER UID HOME SHELL
  while read -r u; do
    IFS=: read -r _ _ uid _ _ home shell < <(getent passwd "$u")
    printf '  %-16s %-6s %-22s %s\n' "$u" "$uid" "$home" "$shell"
  done <<< "$humans"
fi

header "Accounts with UID 0 (should only be root)"
uid0=$(awk -F: '$3 == 0 && $1 != "root" {print $1}' /etc/passwd)
if [[ -z "$uid0" ]]; then
  echo "  OK: only root"
else
  echo "  CRITICAL: $uid0"
  CRITICAL=$((CRITICAL + 1))
fi

header "Members of admin groups"
for g in sudo wheel admin; do
  members=$(getent group "$g" | cut -d: -f4 || true)
  if getent group "$g" >/dev/null; then
    echo "  $g: ${members:-<no members>}"
  fi
done

header "Password status"
if [[ $EUID -ne 0 ]]; then
  echo "  skipped: run as root to read /etc/shadow"
else
  empty=$(awk -F: '$2 == "" {print $1}' /etc/shadow)
  if [[ -n "$empty" ]]; then
    echo "  CRITICAL: accounts with an EMPTY password: $empty"
    CRITICAL=$((CRITICAL + 1))
  else
    echo "  OK: no accounts with an empty password"
  fi
  if [[ -n "$humans" ]]; then
    while read -r u; do
      hash=$(awk -F: -v u="$u" '$1 == u {print $2}' /etc/shadow)
      if [[ "$hash" == '!'* || "$hash" == '*'* ]]; then
        echo "  $u: locked"
      fi
    done <<< "$humans"
  fi
fi

header "Last login of human accounts"
if [[ -z "$humans" ]]; then
  echo "  none"
elif command -v lastlog >/dev/null 2>&1; then
  while read -r u; do
    lastlog -u "$u" 2>/dev/null | tail -n +2 | sed 's/^/  /' || true
  done <<< "$humans"
else
  echo "  lastlog not available; try: last -n 20"
fi

header "Summary"
if (( CRITICAL == 0 )); then
  echo "  No critical findings."
  exit 0
fi
echo "  $CRITICAL critical finding(s). Fix them now:"
echo "    passwd -l <user>      lock an account"
echo "    usermod -u <uid> <user>   give a non-root account its own UID"
exit 1
