#!/usr/bin/env bash
#
# network-check.sh - Troubleshoot connectivity step by step.
#
# Goes through the layers in order: interfaces and IPs, default gateway,
# DNS servers and name resolution, ping, TCP ports and HTTP endpoints,
# then lists the ports this machine is listening on.
#
# Usage:   ./network-check.sh [-H host,host] [-p host:port,...] [-u url,...]
# Example: ./network-check.sh -H github.com -p db.internal:5432,github.com:443 -u https://example.com/health
# Exit code: 0 = all checks passed, 1 = at least one failed

set -euo pipefail

HOSTS="google.com,github.com"
PORTS="github.com:443"
URLS="https://github.com"
TIMEOUT=3
PASS=0
FAIL=0

usage() {
  cat <<EOF
Usage: ${0##*/} [-H hosts] [-p host:port list] [-u urls]

  -H  Comma-separated hosts to resolve and ping (default: $HOSTS)
  -p  Comma-separated host:port pairs to test (default: $PORTS)
  -u  Comma-separated URLs to request (default: $URLS)
  -h  Show this help
EOF
}

header() { printf '\n== %s ==\n' "$1"; }
ok()     { printf '  OK    %s\n' "$*"; PASS=$((PASS + 1)); }
bad()    { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL + 1)); }

while getopts ":H:p:u:h" opt; do
  case "$opt" in
    H) HOSTS=$OPTARG ;;
    p) PORTS=$OPTARG ;;
    u) URLS=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

IFS=, read -ra HOST_LIST <<< "$HOSTS"
IFS=, read -ra PORT_LIST <<< "$PORTS"
IFS=, read -ra URL_LIST  <<< "$URLS"

echo "Network check from $(hostname) at $(date '+%F %T')"

header "Interfaces and IP addresses"
if command -v ip >/dev/null 2>&1; then
  ip -brief address | sed 's/^/  /'
else
  echo "  $(hostname -I 2>/dev/null || echo 'unknown')"
fi

header "Default gateway"
if command -v ip >/dev/null 2>&1; then
  gw=$(ip route show default | awk '{print $3; exit}')
else
  # /proc/net/route stores the gateway as little-endian hex
  hex=$(awk '$2 == "00000000" {print $3; exit}' /proc/net/route)
  gw=""
  if [[ -n "$hex" ]]; then
    gw=$(printf '%d.%d.%d.%d' "0x${hex:6:2}" "0x${hex:4:2}" "0x${hex:2:2}" "0x${hex:0:2}")
  fi
fi
if [[ -n "${gw:-}" ]]; then ok "default gateway is $gw"; else bad "no default gateway"; fi

header "DNS"
servers=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null | tr '\n' ' ')
echo "  Nameservers: ${servers:-none found}"
for host in "${HOST_LIST[@]}"; do
  if addr=$(getent hosts "$host" | awk '{print $1; exit}') && [[ -n "$addr" ]]; then
    ok "$host resolves to $addr"
  else
    bad "$host does not resolve"
  fi
done

header "Ping"
if command -v ping >/dev/null 2>&1; then
  for host in "${HOST_LIST[@]}"; do
    if ping -c 2 -W "$TIMEOUT" "$host" >/dev/null 2>&1; then
      ok "$host answers ping"
    else
      bad "$host does not answer ping (some networks block ICMP; check the ports below too)"
    fi
  done
else
  echo "  ping not installed, skipped"
fi

header "TCP ports"
for pair in "${PORT_LIST[@]}"; do
  host=${pair%:*}
  port=${pair##*:}
  if timeout "$TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
    ok "$host:$port is open"
  else
    bad "$host:$port is closed, filtered or unreachable"
  fi
done

header "HTTP endpoints"
if command -v curl >/dev/null 2>&1; then
  for url in "${URL_LIST[@]}"; do
    result=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time "$TIMEOUT" "$url" || true)
    code=${result%% *}
    if [[ "$code" =~ ^[23] ]]; then
      ok "$url returned $code in ${result#* }s"
    else
      if [[ -z "$code" || "$code" == "000" ]]; then
        bad "$url: no response (connection refused, DNS failure or timeout)"
      else
        bad "$url returned $code"
      fi
    fi
  done
else
  echo "  curl not installed, skipped"
fi

header "Listening ports on this machine"
if command -v ss >/dev/null 2>&1; then
  ss -tulpn 2>/dev/null | sed 's/^/  /'
elif command -v netstat >/dev/null 2>&1; then
  netstat -tulpn 2>/dev/null | sed 's/^/  /'
else
  echo "  ss/netstat not installed (install iproute2), skipped"
fi

header "Summary"
echo "  Passed: $PASS   Failed: $FAIL"
(( FAIL == 0 )) || exit 1
