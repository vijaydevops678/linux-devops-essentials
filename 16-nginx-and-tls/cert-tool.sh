#!/usr/bin/env bash
#
# cert-tool.sh - The openssl tasks DevOps engineers need, without remembering the flags.
#
# Commands:
#   selfsigned <domain> [days]     self-signed certificate + key (dev, internal, testing)
#   csr <domain>                   private key + certificate signing request for a CA
#   inspect <file | host[:port]>   readable summary of a certificate or CSR
#   match <cert> <key>             does this key belong to this certificate?
#   chain <host[:port]>            show the certificate chain a server sends
#
# Usage:   ./cert-tool.sh <command> [arguments]
# Example: ./cert-tool.sh selfsigned myapp.local 365
#          ./cert-tool.sh match myapp.local.crt myapp.local.key
#          ./cert-tool.sh chain github.com

set -euo pipefail

usage() { sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "ERROR: $*" >&2; exit 1; }

command -v openssl >/dev/null 2>&1 || die "openssl is required"

valid_domain() { [[ "$1" =~ ^(\*\.)?[A-Za-z0-9.-]+$ ]] || die "Invalid domain: $1"; }

# Reads a certificate from a file or a live server
fetch() {
  local target=$1 host port
  if [[ -f "$target" ]]; then cat -- "$target"; return; fi
  host=${target%:*}; port=${target##*:}
  [[ "$host" == "$target" ]] && port=443
  timeout 10 openssl s_client -connect "$host:$port" -servername "$host" </dev/null 2>/dev/null | openssl x509 2>/dev/null \
    || die "Could not get a certificate from $host:$port"
}

cmd_selfsigned() {
  local domain=${1:-} days=${2:-365}
  [[ -n "$domain" ]] || die "Usage: $0 selfsigned <domain> [days]"
  valid_domain "$domain"
  [[ "$days" =~ ^[0-9]+$ ]] || die "days must be a number"
  local name=${domain//\*/wildcard}
  openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days "$days" \
    -keyout "$name.key" -out "$name.crt" \
    -subj "/CN=$domain" -addext "subjectAltName=DNS:$domain" 2>/dev/null
  chmod 600 "$name.key"
  echo "Created $name.crt (valid $days days) and $name.key (mode 600)"
  echo "Browsers will warn because no trusted CA signed it. Use Let's Encrypt for public sites."
}

cmd_csr() {
  local domain=${1:-}
  [[ -n "$domain" ]] || die "Usage: $0 csr <domain>"
  valid_domain "$domain"
  local name=${domain//\*/wildcard}
  openssl req -new -newkey rsa:2048 -nodes -sha256 \
    -keyout "$name.key" -out "$name.csr" \
    -subj "/CN=$domain" -addext "subjectAltName=DNS:$domain" 2>/dev/null
  chmod 600 "$name.key"
  echo "Created $name.csr (send this to your CA) and $name.key (keep it secret, mode 600)"
}

cmd_inspect() {
  local target=${1:-}
  [[ -n "$target" ]] || die "Usage: $0 inspect <file | host[:port]>"
  if [[ -f "$target" ]] && grep -q 'CERTIFICATE REQUEST' "$target"; then
    echo "Certificate signing request: $target"
    openssl req -in "$target" -noout -subject | sed 's/^/  /'
    openssl req -in "$target" -noout -text | grep -A1 'Subject Alternative Name' | tail -n 1 | sed 's/^ */  SAN: /' || true
    return
  fi
  local pem end days
  pem=$(fetch "$target")
  end=$(openssl x509 -noout -enddate <<< "$pem" | cut -d= -f2)
  days=$(( ($(date -d "$end" +%s) - $(date +%s)) / 86400 ))
  echo "Certificate: $target"
  openssl x509 -noout -subject -issuer <<< "$pem" | sed 's/^/  /'
  openssl x509 -noout -startdate -enddate <<< "$pem" | sed 's/^/  /'
  echo "  Days left: $days"
  openssl x509 -noout -ext subjectAltName <<< "$pem" 2>/dev/null | tail -n +2 | sed 's/^ */  SAN: /' || true
  openssl x509 -noout -text <<< "$pem" | grep -m1 'Public-Key' | sed 's/^ */  Key: /' || true
  openssl x509 -noout -fingerprint -sha256 <<< "$pem" | sed 's/^/  /'
}

cmd_match() {
  local cert=${1:-} key=${2:-} c k
  [[ -f "$cert" && -f "$key" ]] || die "Usage: $0 match <cert file> <key file>"
  c=$(openssl x509 -in "$cert" -noout -pubkey | openssl sha256 | awk '{print $NF}')
  k=$(openssl pkey -in "$key" -pubout 2>/dev/null | openssl sha256 | awk '{print $NF}')
  if [[ "$c" == "$k" ]]; then
    echo "MATCH: $key belongs to $cert"
  else
    echo "NO MATCH: $key does not belong to $cert (nginx would fail with 'key values mismatch')"
    exit 1
  fi
}

cmd_chain() {
  local target=${1:-} host port
  [[ -n "$target" ]] || die "Usage: $0 chain <host[:port]>"
  host=${target%:*}; port=${target##*:}
  [[ "$host" == "$target" ]] && port=443
  local out
  out=$(timeout 10 openssl s_client -connect "$host:$port" -servername "$host" -showcerts </dev/null 2>/dev/null || true)
  [[ -n "$out" ]] || die "Could not connect to $host:$port"
  echo "Chain sent by $host:$port (0 = the server's own certificate):"
  grep -E '^ *[0-9]+ s:|^ *i:' <<< "$out" | sed 's/^/  /' || true
  local count
  count=$(grep -c 'BEGIN CERTIFICATE' <<< "$out" || true)
  echo "  Certificates sent: $count"
  if (( count < 2 )); then
    echo "  WARNING: only one certificate sent. Unless it is self-signed, the intermediate is missing;"
    echo "  configure nginx with fullchain.pem, not cert.pem."
  fi
  grep -m1 'Verify return code' <<< "$out" | sed 's/^ */  /' || true
}

case "${1:-}" in
  selfsigned) shift; cmd_selfsigned "$@" ;;
  csr)        shift; cmd_csr "$@" ;;
  inspect)    shift; cmd_inspect "$@" ;;
  match)      shift; cmd_match "$@" ;;
  chain)      shift; cmd_chain "$@" ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
