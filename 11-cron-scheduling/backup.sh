#!/usr/bin/env bash
#
# backup.sh - Compressed, verified, rotated backups. Made to run from cron.
#
# Creates <dest>/<name>-YYYYmmdd-HHMMSS.tar.gz plus a .sha256 checksum,
# verifies the archive can be read, deletes backups older than the retention
# period and writes a log. A lock stops two runs from overlapping.
#
# Usage:   ./backup.sh -d dest_dir [-k keep_days] [-n name] source [source ...]
# Example: sudo ./backup.sh -d /backups -k 7 -n etc /etc
#
# Cron (daily at 02:30):
#   30 2 * * * /usr/local/bin/backup.sh -d /backups -k 7 -n etc /etc >> /var/log/backup.log 2>&1
#
# Restore:
#   sha256sum -c etc-20261127-023000.tar.gz.sha256
#   sudo tar -xzf etc-20261127-023000.tar.gz -C /restore-here

set -euo pipefail

DEST=""
KEEP_DAYS=7
NAME="backup"

usage() {
  cat <<EOF
Usage: ${0##*/} -d dest_dir [-k keep_days] [-n name] source [source ...]

  -d dest_dir   Where backups are stored (required)
  -k keep_days  Delete backups older than this (default: $KEEP_DAYS)
  -n name       Prefix for the archive name (default: $NAME)
  -h            Show this help
EOF
}

log() { echo "$(date '+%F %T') $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

while getopts ":d:k:n:h" opt; do
  case "$opt" in
    d) DEST=$OPTARG ;;
    k) KEEP_DAYS=$OPTARG ;;
    n) NAME=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

[[ -n "$DEST" && $# -gt 0 ]] || { usage; exit 1; }
[[ "$KEEP_DAYS" =~ ^[0-9]+$ ]] || die "-k must be a number of days"
[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "-n may only contain letters, numbers, . _ -"
for src in "$@"; do
  [[ -e "$src" ]] || die "Source not found: $src"
done

mkdir -p "$DEST"

# Only one backup at a time (cron may start a new run before the last one ends)
exec 9> "$DEST/.backup-$NAME.lock"
flock -n 9 || die "Another backup named '$NAME' is already running"

ARCHIVE="$DEST/$NAME-$(date +%Y%m%d-%H%M%S).tar.gz"
while [[ -e "$ARCHIVE" ]]; do   # two runs in the same second: wait for a new name
  sleep 1
  ARCHIVE="$DEST/$NAME-$(date +%Y%m%d-%H%M%S).tar.gz"
done
START=$(date +%s)

log "Starting backup of: $*"
if ! tar -czf "$ARCHIVE" "$@" 2> "$ARCHIVE.err"; then
  cat "$ARCHIVE.err" >&2
  rm -f "$ARCHIVE" "$ARCHIVE.err"
  die "tar failed"
fi
rm -f "$ARCHIVE.err"

log "Verifying archive"
tar -tzf "$ARCHIVE" >/dev/null || die "Archive is corrupt: $ARCHIVE"

(cd "$DEST" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")

SIZE=$(du -h "$ARCHIVE" | cut -f1)
log "Created $ARCHIVE ($SIZE) in $(( $(date +%s) - START ))s"

log "Removing backups older than $KEEP_DAYS days"
deleted=0
while IFS= read -r -d '' old; do
  rm -f -- "$old" "$old.sha256"
  log "  deleted $(basename "$old")"
  deleted=$((deleted + 1))
done < <(find "$DEST" -maxdepth 1 -type f -name "$NAME-*.tar.gz" -mtime +"$KEEP_DAYS" -print0)

count=$(find "$DEST" -maxdepth 1 -type f -name "$NAME-*.tar.gz" | wc -l)
log "Done. Removed $deleted old backup(s); $count backup(s) kept in $DEST"
