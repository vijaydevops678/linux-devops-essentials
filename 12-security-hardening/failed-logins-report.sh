#!/usr/bin/env bash
#
# failed-logins-report.sh - Who is trying to break into your server over SSH?
#
# Reads the auth log (or the systemd journal) and reports failed password
# attempts, the attacking IPs, the usernames they tried, successful logins,
# and the commands to block the worst offenders.
#
# Usage:   sudo ./failed-logins-report.sh [-n top] [-b block_after] [logfile]
# Example: ./failed-logins-report.sh sample-auth.log
#          sudo ./failed-logins-report.sh                (auto-detects the log)

set -euo pipefail

TOP=10
BLOCK_AFTER=10

usage() {
  cat <<EOF
Usage: ${0##*/} [-n top] [-b block_after] [logfile]

  -n top          Entries per list (default: $TOP)
  -b block_after  Suggest blocking IPs with at least this many failures (default: $BLOCK_AFTER)
  -h              Show this help
  logfile         Default: /var/log/auth.log, /var/log/secure, or the systemd journal
EOF
}

while getopts ":n:b:h" opt; do
  case "$opt" in
    n) TOP=$OPTARG ;;
    b) BLOCK_AFTER=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

DATA=$(mktemp)
trap 'rm -f "$DATA"' EXIT

if [[ $# -gt 0 ]]; then
  SOURCE=$1
  cat -- "$SOURCE" > "$DATA"
elif [[ -r /var/log/auth.log ]]; then
  SOURCE=/var/log/auth.log
  cat "$SOURCE" > "$DATA"
elif [[ -r /var/log/secure ]]; then
  SOURCE=/var/log/secure
  cat "$SOURCE" > "$DATA"
elif command -v journalctl >/dev/null 2>&1; then
  SOURCE="journalctl (ssh, last 7 days)"
  journalctl -u ssh -u sshd --since "7 days ago" --no-pager > "$DATA" 2>/dev/null || true
else
  echo "No auth log found; pass a log file as an argument" >&2
  exit 1
fi

header() { printf '\n== %s ==\n' "$1"; }
top() { sort | uniq -c | sort -rn | head -n "$TOP" || true; }

# "Failed password for [invalid user] NAME from IP port N ssh2"
failed=$(grep -E 'Failed password for' "$DATA" \
  | sed -E 's/.*Failed password for (invalid user )?([^ ]+) from ([0-9a-fA-F.:]+).*/\2 \3/' || true)
accepted=$(grep -E 'Accepted (password|publickey) for' "$DATA" \
  | sed -E 's/.*Accepted ([a-z]+) for ([^ ]+) from ([0-9a-fA-F.:]+).*/\2 \3 \1/' || true)
invalid=$(grep -c 'Invalid user' "$DATA" || true)

count_lines() { if [[ -z "$1" ]]; then echo 0; else wc -l <<< "$1"; fi; }
total_failed=$(count_lines "$failed")
unique_ips=0
[[ -n "$failed" ]] && unique_ips=$(awk '{print $2}' <<< "$failed" | sort -u | wc -l)

echo "SSH login report from: $SOURCE"
header "Overview"
printf '  %-28s %s\n' "Failed password attempts:" "$total_failed"
printf '  %-28s %s\n' "Attempts on unknown users:" "$invalid"
printf '  %-28s %s\n' "Attacking IP addresses:" "$unique_ips"
printf '  %-28s %s\n' "Successful logins:" "$(count_lines "$accepted")"

if [[ -n "$failed" ]]; then
  header "Top $TOP attacking IPs"
  awk '{print $2}' <<< "$failed" | top

  header "Top $TOP usernames tried"
  awk '{print $1}' <<< "$failed" | top
fi

header "Successful logins (user, IP, method)"
if [[ -z "$accepted" ]]; then
  echo "  none"
else
  sort <<< "$accepted" | uniq -c | sort -rn | head -n "$TOP"
  if grep -q ' password$' <<< "$accepted"; then
    echo "  Note: password logins succeeded. Switch to SSH keys and set PasswordAuthentication no."
  fi
fi

if [[ -n "$failed" ]]; then
  header "IPs with $BLOCK_AFTER or more failures: block them"
  offenders=$(awk '{print $2}' <<< "$failed" | sort | uniq -c | awk -v n="$BLOCK_AFTER" '$1 >= n {print $2}')
  if [[ -z "$offenders" ]]; then
    echo "  none"
  else
    while read -r ip; do
      echo "  sudo ufw deny from $ip          # Ubuntu"
      echo "  sudo firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=$ip reject'   # RHEL"
    done <<< "$offenders"
    echo "  Better long-term: install fail2ban to block brute-force IPs automatically."
  fi
fi
