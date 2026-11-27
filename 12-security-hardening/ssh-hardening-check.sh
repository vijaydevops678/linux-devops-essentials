#!/usr/bin/env bash
#
# ssh-hardening-check.sh - Check an SSH server configuration against best practices.
#
# Uses the effective settings from `sshd -T` when run as root on a server
# with OpenSSH, otherwise reads the config files (first value wins, like sshd).
# Each setting gets PASS / WARN / FAIL with the fix to apply.
#
# Usage:   sudo ./ssh-hardening-check.sh
#          ./ssh-hardening-check.sh -f /path/to/sshd_config      (check a file)
# Exit code: 0 = no FAIL, 1 = at least one FAIL

set -euo pipefail

CONFIG=/etc/ssh/sshd_config
USE_FILE=false
PASSED=0
WARNED=0
FAILED=0
SETTINGS=""

usage() {
  cat <<EOF
Usage: ${0##*/} [-f sshd_config]

  -f file  Check this config file instead of the running server
  -h       Show this help
EOF
}

while getopts ":f:h" opt; do
  case "$opt" in
    f) CONFIG=$OPTARG; USE_FILE=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ "$USE_FILE" == false && $EUID -eq 0 ]] && command -v sshd >/dev/null 2>&1; then
  SETTINGS=$(sshd -T 2>/dev/null || true)
  [[ -n "$SETTINGS" ]] && echo "Source: effective settings from 'sshd -T'"
fi

if [[ -z "$SETTINGS" ]]; then
  [[ -r "$CONFIG" ]] || { echo "Cannot read $CONFIG" >&2; exit 1; }
  files=()
  if [[ "$USE_FILE" == false ]]; then
    # Ubuntu/Debian include these at the top of sshd_config, so they win
    for f in /etc/ssh/sshd_config.d/*.conf; do
      [[ -r "$f" ]] && files+=("$f")
    done
  fi
  files+=("$CONFIG")
  echo "Source: ${files[*]}"
  SETTINGS=$(cat "${files[@]}" \
    | sed 's/#.*//' \
    | awk 'NF >= 2 {key = tolower($1); if (!(key in seen)) {seen[key] = 1; $1 = ""; sub(/^ /, ""); print key, tolower($0)}}')
fi

# get <key> <OpenSSH default>
get() {
  local value
  value=$(awk -v k="$1" '$1 == k {$1 = ""; sub(/^ /, ""); print; exit}' <<< "$SETTINGS")
  echo "${value:-$2}"
}

pass() { printf '  PASS  %-24s %s\n' "$1" "$2"; PASSED=$((PASSED + 1)); }
warn() { printf '  WARN  %-24s %s\n        fix: %s\n' "$1" "$2" "$3"; WARNED=$((WARNED + 1)); }
fail() { printf '  FAIL  %-24s %s\n        fix: %s\n' "$1" "$2" "$3"; FAILED=$((FAILED + 1)); }
info() { printf '  INFO  %-24s %s\n' "$1" "$2"; }

to_seconds() {
  local v=$1
  case "$v" in
    *m) echo $(( ${v%m} * 60 )) ;;
    *s) echo "${v%s}" ;;
    *)  echo "$v" ;;
  esac
}

echo
v=$(get permitrootlogin prohibit-password)
case "$v" in
  no) pass PermitRootLogin "$v" ;;
  prohibit-password|without-password)
      warn PermitRootLogin "$v (root can still log in with a key)" "PermitRootLogin no" ;;
  *)  fail PermitRootLogin "$v" "PermitRootLogin no" ;;
esac

v=$(get passwordauthentication yes)
if [[ "$v" == no ]]; then pass PasswordAuthentication "$v"
else fail PasswordAuthentication "$v (brute-force target)" "PasswordAuthentication no (set up SSH keys first!)"; fi

v=$(get permitemptypasswords no)
if [[ "$v" == no ]]; then pass PermitEmptyPasswords "$v"
else fail PermitEmptyPasswords "$v" "PermitEmptyPasswords no"; fi

v=$(get pubkeyauthentication yes)
if [[ "$v" == yes ]]; then pass PubkeyAuthentication "$v"
else fail PubkeyAuthentication "$v" "PubkeyAuthentication yes"; fi

v=$(get kbdinteractiveauthentication yes)
if [[ "$v" == no ]]; then pass KbdInteractiveAuth "$v"
else warn KbdInteractiveAuth "$v (another password prompt)" "KbdInteractiveAuthentication no"; fi

v=$(get maxauthtries 6)
if (( v <= 4 )); then pass MaxAuthTries "$v"
else warn MaxAuthTries "$v" "MaxAuthTries 3"; fi

v=$(get x11forwarding no)
if [[ "$v" == no ]]; then pass X11Forwarding "$v"
else warn X11Forwarding "$v (rarely needed on servers)" "X11Forwarding no"; fi

v=$(get logingracetime 120)
if (( $(to_seconds "$v") <= 60 )); then pass LoginGraceTime "$v"
else warn LoginGraceTime "$v (unauthenticated connections stay open long)" "LoginGraceTime 30"; fi

v=$(get clientaliveinterval 0)
if (( v > 0 )); then pass ClientAliveInterval "$v"
else warn ClientAliveInterval "$v (idle sessions never time out)" "ClientAliveInterval 300 and ClientAliveCountMax 2"; fi

v=$(get allowusers "")
g=$(get allowgroups "")
if [[ -n "$v" || -n "$g" ]]; then pass "AllowUsers/AllowGroups" "${v:-}${g:+ groups: $g}"
else info "AllowUsers/AllowGroups" "not set (consider limiting who can log in: AllowGroups sshusers)"; fi

info Port "$(get port 22) (a different port reduces log noise, it is not real protection)"

echo
echo "Result: $PASSED passed, $WARNED warnings, $FAILED failed"
if (( FAILED + WARNED > 0 )); then
  echo "Apply fixes in /etc/ssh/sshd_config.d/99-hardening.conf, then:"
  echo "  sudo sshd -t && sudo systemctl reload ssh     (keep your current session open while testing!)"
fi
(( FAILED == 0 )) || exit 1
