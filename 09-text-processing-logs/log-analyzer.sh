#!/usr/bin/env bash
#
# log-analyzer.sh - Turn an Nginx/Apache access log into a traffic report.
#
# Works on the standard "combined" log format, plain or gzipped:
#   203.0.113.7 - - [27/Nov/2026:10:15:32 +0530] "GET /api/users HTTP/1.1" 200 512 "-" "curl/8.5"
#
# Reports totals, status codes, error rate, top IPs, top URLs, failing URLs,
# requests per hour, top user agents and suspicious requests.
#
# Usage:   ./log-analyzer.sh [-n top] access.log [more.log access.log.1.gz ...]
# Example: ./log-analyzer.sh sample-access.log
#          sudo ./log-analyzer.sh -n 5 /var/log/nginx/access.log*

set -euo pipefail

TOP=10

usage() {
  cat <<EOF
Usage: ${0##*/} [-n top] logfile [logfile ...]

  -n top   How many entries to show in each "top" list (default: $TOP)
  -h       Show this help
EOF
}

while getopts ":n:h" opt; do
  case "$opt" in
    n) TOP=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -gt 0 ]] || { usage; exit 1; }

# Read all logs (plain or .gz) into one temporary file
DATA=$(mktemp)
trap 'rm -f "$DATA"' EXIT
for f in "$@"; do
  [[ -r "$f" ]] || { echo "Cannot read $f" >&2; exit 1; }
  if [[ "$f" == *.gz ]]; then zcat -- "$f"; else cat -- "$f"; fi
done > "$DATA"

TOTAL=$(wc -l < "$DATA")
(( TOTAL > 0 )) || { echo "No log lines found"; exit 0; }

header() { printf '\n== %s ==\n' "$1"; }
# count -> sort by frequency -> keep the top entries
top() { sort | uniq -c | sort -rn | head -n "$TOP" || true; }

first=$(head -n 1 "$DATA" | awk -F'[][]' '{print $2}')
last=$(tail -n 1 "$DATA" | awk -F'[][]' '{print $2}')
unique_ips=$(awk '{print $1}' "$DATA" | sort -u | wc -l)
bytes=$(awk '$10 ~ /^[0-9]+$/ {sum += $10} END {print sum + 0}' "$DATA")
errors4=$(awk '$9 ~ /^4/' "$DATA" | wc -l)
errors5=$(awk '$9 ~ /^5/' "$DATA" | wc -l)

echo "Access log report: $*"
header "Overview"
printf '  %-18s %s\n' "Time range:" "$first  ->  $last"
printf '  %-18s %s\n' "Total requests:" "$TOTAL"
printf '  %-18s %s\n' "Unique visitors:" "$unique_ips"
printf '  %-18s %s\n' "Data sent:" "$(numfmt --to=iec "$bytes")B"
printf '  %-18s %s (%s%%)\n' "4xx client errors:" "$errors4" "$(awk -v e="$errors4" -v t="$TOTAL" 'BEGIN {printf "%.1f", e * 100 / t}')"
printf '  %-18s %s (%s%%)\n' "5xx server errors:" "$errors5" "$(awk -v e="$errors5" -v t="$TOTAL" 'BEGIN {printf "%.1f", e * 100 / t}')"

header "Status codes"
awk '{print $9}' "$DATA" | top

header "Top $TOP IP addresses"
awk '{print $1}' "$DATA" | top

header "Top $TOP requested URLs"
awk '{print $7}' "$DATA" | top

header "Top $TOP URLs returning 5xx"
awk '$9 ~ /^5/ {print $9, $7}' "$DATA" | top

header "Requests per hour"
awk '{split($4, t, ":"); print t[2] ":00"}' "$DATA" | sort | uniq -c \
  | awk '{bar = ""; for (i = 0; i < $1 / 2; i++) bar = bar "#"; printf "  %s %5d %s\n", $2, $1, bar}'

header "Top $TOP user agents"
awk -F'"' '{print $6}' "$DATA" | top

header "Suspicious requests (scanners, injection attempts)"
suspicious=$(grep -Eic "wp-login|wp-admin|\.env|/etc/passwd|\.\./|union.*select|<script|phpmyadmin|\.git/" "$DATA" || true)
echo "  $suspicious request(s) matched common attack patterns. By IP:"
grep -Ei "wp-login|wp-admin|\.env|/etc/passwd|\.\./|union.*select|<script|phpmyadmin|\.git/" "$DATA" \
  | awk '{print $1}' | top || true
