#!/usr/bin/env bash
#
# ssl-expiry-check.sh - Never get surprised by an expired certificate again.
#
# Checks TLS certificates of websites (host or host:port) or local
# certificate files: days until expiry, issuer, and whether the hostname is
# covered by the certificate. Grades each one OK / WARN / CRIT.
#
# Usage:   ./ssl-expiry-check.sh [-w days] [-c days] [-f file] [-W webhook] [target ...]
#          target = example.com | example.com:8443 | /path/to/cert.pem
# Example: ./ssl-expiry-check.sh github.com example.com:443
#          ./ssl-expiry-check.sh -f domains.txt -w 30 -c 7
# Exit code: 0 = all OK, 1 = warnings, 2 = critical, expired or unreachable

set -euo pipefail

WARN_DAYS=30
CRIT_DAYS=7
LIST_FILE=""
WEBHOOK=""
TIMEOUT=10
WORST=0
ALERTS=()

usage() { sed -n '3,15p' "$0" | sed 's/^# \{0,1\}//'; }

while getopts ":w:c:f:W:h" opt; do
  case "$opt" in
    w) WARN_DAYS=$OPTARG ;;
    c) CRIT_DAYS=$OPTARG ;;
    f) LIST_FILE=$OPTARG ;;
    W) WEBHOOK=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 2; }

TARGETS=("$@")
if [[ -n "$LIST_FILE" ]]; then
  [[ -r "$LIST_FILE" ]] || { echo "Cannot read $LIST_FILE" >&2; exit 2; }
  while read -r line; do
    line=${line%%#*}
    line=${line//[[:space:]]/}
    [[ -n "$line" ]] && TARGETS+=("$line")
  done < "$LIST_FILE"
fi
[[ ${#TARGETS[@]} -gt 0 ]] || { usage; exit 2; }

# get_cert <target> : prints the PEM certificate
get_cert() {
  local target=$1 host port
  if [[ -f "$target" ]]; then
    cat -- "$target"
    return
  fi
  host=${target%:*}
  port=${target##*:}
  [[ "$host" == "$target" ]] && port=443
  timeout "$TIMEOUT" openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null \
    | openssl x509 2>/dev/null
}

# covers <hostname> <SAN list> : does the certificate cover this name (including *.wildcards)?
covers() {
  local name=$1 sans=$2 san san_list
  IFS=',' read -ra san_list <<< "$sans"
  for san in "${san_list[@]}"; do
    san=${san#DNS:}
    if [[ "$san" == "$name" ]]; then return 0; fi
    if [[ "$san" == \*.* && "${name#*.}" == "${san#\*.}" ]]; then return 0; fi
  done
  return 1
}

set_level() { (( $1 > WORST )) && WORST=$1; return 0; }

printf '%-32s %-6s %6s  %-12s %-28s %s\n' TARGET STATUS DAYS EXPIRES ISSUER NOTE
now=$(date +%s)
for target in "${TARGETS[@]}"; do
  pem=$(get_cert "$target" || true)
  if [[ -z "$pem" ]]; then
    printf '%-32s %-6s %6s  %-12s %-28s %s\n' "$target" ERROR - - - "no certificate (unreachable, not TLS, or not a PEM file)"
    set_level 2
    ALERTS+=("$target: unreachable or no certificate")
    continue
  fi

  end=$(openssl x509 -noout -enddate <<< "$pem" | cut -d= -f2)
  issuer_dn=$(openssl x509 -noout -issuer -nameopt RFC2253 <<< "$pem")
  subject_dn=$(openssl x509 -noout -subject -nameopt RFC2253 <<< "$pem")
  org=$(grep -o 'O=[^,]*' <<< "$issuer_dn" | head -n 1 | cut -d= -f2 || true)
  cn=$(grep -o 'CN=[^,]*' <<< "$issuer_dn" | head -n 1 | cut -d= -f2 || true)
  issuer=$(cut -c1-28 <<< "${org:-${cn:-unknown}}")
  sans=$(openssl x509 -noout -ext subjectAltName <<< "$pem" 2>/dev/null | tail -n +2 | tr -d ' ' || true)
  end_ts=$(date -d "$end" +%s)
  days=$(( (end_ts - now) / 86400 ))
  expires=$(date -d "$end" +%F)

  note=""
  if [[ ! -f "$target" ]]; then
    host=${target%:*}
    if ! covers "$host" "$sans"; then
      note="hostname NOT in certificate (${sans:-no SAN})"
      set_level 2
      ALERTS+=("$target: certificate does not cover $host")
    fi
  fi
  if [[ "${issuer_dn#issuer=}" == "${subject_dn#subject=}" ]]; then
    note="${note:+$note; }self-signed"
  fi

  if (( days < 0 )); then
    status=CRIT; note="${note:+$note; }EXPIRED"; set_level 2
    ALERTS+=("$target: EXPIRED on $expires")
  elif (( days <= CRIT_DAYS )); then
    status=CRIT; set_level 2
    ALERTS+=("$target: expires in $days days")
  elif (( days <= WARN_DAYS )); then
    status=WARN; set_level 1
    ALERTS+=("$target: expires in $days days")
  else
    status=OK
  fi
  printf '%-32s %-6s %6s  %-12s %-28s %s\n' "$target" "$status" "$days" "$expires" "$issuer" "$note"
done

if [[ -n "$WEBHOOK" && ${#ALERTS[@]} -gt 0 ]]; then
  text="Certificate check on $(hostname): $(IFS=';'; echo "${ALERTS[*]}")"
  text=${text//\"/\\\"}
  curl -fsS -m 10 -X POST -H 'Content-Type: application/json' --data "{\"text\": \"$text\"}" "$WEBHOOK" >/dev/null \
    || echo "Could not send webhook alert" >&2
fi

exit "$WORST"
