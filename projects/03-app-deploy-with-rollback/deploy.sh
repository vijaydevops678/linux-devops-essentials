#!/usr/bin/env bash
#
# deploy.sh - Zero-downtime releases with health checks and automatic rollback.
#
# Uses the "releases + current symlink" layout (the same idea as Capistrano,
# Deployer and many CI/CD pipelines):
#
#   $APP_DIR/
#   ├── releases/
#   │   ├── 20261127-101500/
#   │   └── 20261127-120000/
#   ├── shared/            files kept between releases (.env, uploads, logs)
#   └── current -> releases/20261127-120000
#
# Switching `current` is a single atomic rename, so users never see a
# half-copied release. If the health check fails, the previous release is
# restored automatically.
#
# Usage:
#   ./deploy.sh deploy <source_dir | app.tar.gz>
#   ./deploy.sh rollback
#   ./deploy.sh list
#   ./deploy.sh status
#
# Settings (environment variables):
#   APP_DIR=/opt/myapp        where releases live
#   KEEP_RELEASES=5           how many releases to keep
#   SERVICE_NAME=             systemd service to restart after switching (optional)
#   HEALTH_URL=               URL that must return 2xx after a deploy (optional)
#   HEALTH_RETRIES=5          attempts, 2 seconds apart
#
# Example:
#   APP_DIR=/opt/myapp SERVICE_NAME=myapp HEALTH_URL=http://localhost:8080/health ./deploy.sh deploy ./build

set -euo pipefail

APP_DIR=${APP_DIR:-/opt/myapp}
KEEP_RELEASES=${KEEP_RELEASES:-5}
SERVICE_NAME=${SERVICE_NAME:-}
HEALTH_URL=${HEALTH_URL:-}
HEALTH_RETRIES=${HEALTH_RETRIES:-5}

RELEASES="$APP_DIR/releases"
SHARED="$APP_DIR/shared"
CURRENT="$APP_DIR/current"

log() { echo "$(date '+%F %T') $*"; }
die() { log "ERROR: $*" >&2; exit 1; }
usage() { sed -n '3,33p' "$0" | sed 's/^# \{0,1\}//'; }

current_release() { if [[ -L "$CURRENT" ]]; then basename "$(readlink "$CURRENT")"; fi; }

# Releases sorted oldest -> newest (names are timestamps, so they sort correctly)
list_releases() {
  if [[ -d "$RELEASES" ]]; then
    find "$RELEASES" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
  fi
}

switch_to() {
  local release=$1
  # Atomic switch: build the new link beside the old one, then rename over it
  ln -sfn "$RELEASES/$release" "$APP_DIR/.current.tmp"
  mv -Tf "$APP_DIR/.current.tmp" "$CURRENT"
  log "current -> releases/$release"
  if [[ -n "$SERVICE_NAME" ]]; then
    log "Restarting $SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"
  fi
}

health_check() {
  [[ -n "$HEALTH_URL" ]] || { log "No HEALTH_URL set, skipping health check"; return 0; }
  local i
  for (( i = 1; i <= HEALTH_RETRIES; i++ )); do
    if curl -fs -m 5 -o /dev/null "$HEALTH_URL"; then
      log "Health check passed ($HEALTH_URL)"
      return 0
    fi
    if (( i < HEALTH_RETRIES )); then
      log "Health check attempt $i/$HEALTH_RETRIES failed, retrying in 2s"
      sleep 2
    else
      log "Health check attempt $i/$HEALTH_RETRIES failed"
    fi
  done
  return 1
}

cleanup_old() {
  local releases keep_from current r
  mapfile -t releases < <(list_releases)
  (( ${#releases[@]} > KEEP_RELEASES )) || return 0
  keep_from=$(( ${#releases[@]} - KEEP_RELEASES ))
  current=$(current_release)
  for r in "${releases[@]:0:keep_from}"; do
    [[ "$r" == "$current" ]] && continue
    rm -rf -- "${RELEASES:?}/$r"
    log "Removed old release $r"
  done
}

cmd_deploy() {
  local source=${1:-}
  [[ -n "$source" ]] || die "Usage: $0 deploy <source_dir | app.tar.gz>"
  [[ -e "$source" ]] || die "Source not found: $source"

  mkdir -p "$RELEASES" "$SHARED"
  exec 9> "$APP_DIR/.deploy.lock"
  flock -n 9 || die "Another deploy is running"

  local release previous
  release=$(date +%Y%m%d-%H%M%S)
  while [[ -e "$RELEASES/$release" ]]; do sleep 1; release=$(date +%Y%m%d-%H%M%S); done
  previous=$(current_release)

  log "Deploying release $release (previous: ${previous:-none})"
  mkdir -p "$RELEASES/$release"
  if [[ -d "$source" ]]; then
    cp -a "$source/." "$RELEASES/$release/"
  elif [[ "$source" == *.tar.gz || "$source" == *.tgz ]]; then
    tar -xzf "$source" -C "$RELEASES/$release"
  else
    rm -rf -- "${RELEASES:?}/$release"
    die "Source must be a directory or a .tar.gz file"
  fi

  # Link shared files (config, uploads) into the release
  local item
  for item in "$SHARED"/* "$SHARED"/.env; do
    [[ -e "$item" ]] || continue
    ln -sfn "$item" "$RELEASES/$release/$(basename "$item")"
    log "Linked shared/$(basename "$item")"
  done

  switch_to "$release"

  if health_check; then
    cleanup_old
    log "Deploy of $release succeeded"
    return 0
  fi

  if [[ -n "$previous" && -d "$RELEASES/$previous" ]]; then
    log "Health check FAILED: rolling back to $previous"
    switch_to "$previous"
    rm -rf -- "${RELEASES:?}/$release"
    log "Removed failed release $release"
  else
    log "Health check FAILED and there is no previous release to roll back to"
  fi
  exit 1
}

cmd_rollback() {
  local releases current i target=""
  mapfile -t releases < <(list_releases)
  current=$(current_release)
  [[ -n "$current" ]] || die "Nothing is deployed yet"
  for (( i = ${#releases[@]} - 1; i >= 0; i-- )); do
    if [[ "${releases[i]}" == "$current" ]] && (( i > 0 )); then
      target=${releases[i - 1]}
      break
    fi
  done
  [[ -n "$target" ]] || die "No older release to roll back to"
  log "Rolling back from $current to $target"
  switch_to "$target"
  health_check || die "Rolled back, but the health check still fails"
}

cmd_list() {
  local current r
  current=$(current_release)
  if [[ -z "$(list_releases)" ]]; then
    echo "No releases in $RELEASES"
    return 0
  fi
  while read -r r; do
    if [[ "$r" == "$current" ]]; then echo "* $r  (current)"; else echo "  $r"; fi
  done < <(list_releases)
}

cmd_status() {
  local current
  current=$(current_release)
  echo "App directory:  $APP_DIR"
  echo "Current:        ${current:-none}"
  echo "Releases:       $(list_releases | wc -l) (keeping $KEEP_RELEASES)"
  echo "Service:        ${SERVICE_NAME:-not set}"
  echo "Health URL:     ${HEALTH_URL:-not set}"
  if [[ -n "$HEALTH_URL" ]]; then
    if curl -fs -m 5 -o /dev/null "$HEALTH_URL"; then echo "Health:         OK"; else echo "Health:         FAILING"; fi
  fi
}

case "${1:-}" in
  deploy)   shift; cmd_deploy "$@" ;;
  rollback) cmd_rollback ;;
  list)     cmd_list ;;
  status)   cmd_status ;;
  -h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
