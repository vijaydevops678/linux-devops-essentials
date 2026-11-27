#!/usr/bin/env bash
#
# cleanup-old-files.sh - Safely delete or compress old files (logs, temp files, artifacts).
#
# Dry run by default: it only lists what matches. Add -x to delete or -z to
# gzip the matching files. Refuses to run on / and other system directories.
#
# Usage:   ./cleanup-old-files.sh -d dir [-a days] [-p pattern] [-x | -z]
# Example: ./cleanup-old-files.sh -d /var/log/myapp -a 14 -p "*.log"        (list only)
#          sudo ./cleanup-old-files.sh -d /var/log/myapp -a 14 -p "*.log" -z   (compress)
#          sudo ./cleanup-old-files.sh -d /tmp/builds -a 3 -p "*" -x           (delete)

set -euo pipefail

DIR=""
AGE=7
PATTERN="*.log"
ACTION="list"

usage() {
  cat <<EOF
Usage: ${0##*/} -d dir [-a days] [-p pattern] [-x | -z]

  -d dir      Directory to clean (required)
  -a days     Only files last modified more than this many days ago (default: $AGE)
  -p pattern  File name pattern, quoted (default: "$PATTERN")
  -x          Delete the matching files
  -z          Compress the matching files with gzip instead of deleting
  -h          Show this help
Without -x or -z nothing is changed.
EOF
}

while getopts ":d:a:p:xzh" opt; do
  case "$opt" in
    d) DIR=$OPTARG ;;
    a) AGE=$OPTARG ;;
    p) PATTERN=$OPTARG ;;
    x) ACTION="delete" ;;
    z) ACTION="compress" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

[[ -n "$DIR" ]] || { usage; exit 1; }
[[ -d "$DIR" ]] || { echo "Not a directory: $DIR" >&2; exit 1; }
[[ "$AGE" =~ ^[0-9]+$ ]] || { echo "-a must be a number of days" >&2; exit 1; }

DIR=$(realpath "$DIR")
case "$DIR" in
  /|/bin|/boot|/dev|/etc|/lib|/lib64|/proc|/root|/sbin|/sys|/usr|/var|/home)
    echo "Refusing to clean a system directory: $DIR" >&2
    exit 1 ;;
esac

find_args=("$DIR" -type f -name "$PATTERN" -mtime +"$AGE")
if [[ "$ACTION" == "compress" ]]; then
  find_args+=(! -name "*.gz")
fi

mapfile -d '' files < <(find "${find_args[@]}" -print0 2>/dev/null)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files matching '$PATTERN' older than $AGE days in $DIR"
  exit 0
fi

total=0
for f in "${files[@]}"; do
  size=$(stat -c '%s' "$f")
  total=$((total + size))
  printf '  %8s  %s  %s\n' "$(numfmt --to=iec --suffix=B "$size")" "$(date -r "$f" '+%F')" "$f"
done
echo "${#files[@]} file(s), $(numfmt --to=iec --suffix=B "$total") in total"

case "$ACTION" in
  list)
    echo "Dry run: nothing changed. Add -x to delete or -z to compress." ;;
  delete)
    for f in "${files[@]}"; do rm -f -- "$f"; done
    echo "Deleted ${#files[@]} file(s), freed $(numfmt --to=iec --suffix=B "$total")." ;;
  compress)
    for f in "${files[@]}"; do gzip -- "$f"; done
    echo "Compressed ${#files[@]} file(s)." ;;
esac
