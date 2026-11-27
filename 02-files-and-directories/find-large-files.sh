#!/usr/bin/env bash
#
# find-large-files.sh - Find what is eating your disk space.
#
# Shows the filesystem usage, the biggest directories and the biggest files
# under a path. Stays on one filesystem (-xdev), so /proc and network mounts
# are skipped.
#
# Usage:   ./find-large-files.sh [-n count] [-s min_size] [path]
# Example: sudo ./find-large-files.sh -n 20 -s 500M /var

set -euo pipefail

COUNT=10
MIN_SIZE="100M"

usage() {
  cat <<EOF
Usage: ${0##*/} [-n count] [-s min_size] [path]

  -n count     How many directories and files to show (default: $COUNT)
  -s min_size  Only list files bigger than this, e.g. 50M, 1G (default: $MIN_SIZE)
  -h           Show this help
  path         Where to look (default: current directory)
EOF
}

while getopts ":n:s:h" opt; do
  case "$opt" in
    n) COUNT=$OPTARG ;;
    s) MIN_SIZE=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
TARGET=${1:-.}

[[ -d "$TARGET" ]] || { echo "Not a directory: $TARGET" >&2; exit 1; }
[[ "$COUNT" =~ ^[0-9]+$ ]] || { echo "-n must be a number" >&2; exit 1; }
[[ "$MIN_SIZE" =~ ^[0-9]+[kMG]$ ]] || { echo "-s must look like 500k, 100M or 2G" >&2; exit 1; }

echo "Disk usage report for: $(realpath "$TARGET")"
echo
echo "== Filesystem =="
df -h "$TARGET"

echo
echo "== Top $COUNT directories =="
du -xh --max-depth=1 "$TARGET" 2>/dev/null | sort -rh | head -n "$COUNT" || true

echo
echo "== Top $COUNT files larger than $MIN_SIZE =="
results=$(find "$TARGET" -xdev -type f -size +"$MIN_SIZE" -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -n "$COUNT" || true)

if [[ -z "$results" ]]; then
  echo "  none found"
else
  while IFS=$'\t' read -r bytes file; do
    printf '  %8s  %s\n' "$(numfmt --to=iec "$bytes")" "$file"
  done <<< "$results"
fi

echo
echo "== Files changed in the last 24 hours (top $COUNT by size) =="
recent=$(find "$TARGET" -xdev -type f -mtime -1 -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -n "$COUNT" || true)
if [[ -z "$recent" ]]; then
  echo "  none"
else
  while IFS=$'\t' read -r bytes file; do
    printf '  %8s  %s\n' "$(numfmt --to=iec "$bytes")" "$file"
  done <<< "$recent"
fi
