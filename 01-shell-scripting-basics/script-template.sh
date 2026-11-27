#!/usr/bin/env bash
#
# script-template.sh - A production-ready starting point for any bash script.
#
# Copy this file whenever you start a new script. It gives you strict mode,
# timestamped logging, option parsing, a dry-run mode, dependency checks
# and automatic cleanup on exit.
#
# Usage:   ./script-template.sh [-n] [-v] [-h] <name>
# Example: ./script-template.sh -v world

set -euo pipefail   # stop on errors, on unset variables, and on failures inside pipes

readonly SCRIPT_NAME="${0##*/}"
DRY_RUN=false
VERBOSE=false
TMP_DIR=""

# ---------- logging (to stderr, so stdout stays clean for real output) ----------
log()   { printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${*:2}" >&2; }
info()  { log INFO "$@"; }
warn()  { log WARN "$@"; }
error() { log ERROR "$@"; }
debug() { if [[ "$VERBOSE" == true ]]; then log DEBUG "$@"; fi; }
die()   { error "$@"; exit 1; }

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options] <name>

Options:
  -n    Dry run: show what would happen without changing anything
  -v    Verbose output
  -h    Show this help
EOF
}

# Runs a command, or only prints it in dry-run mode
run() {
  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] $*"
  else
    debug "running: $*"
    "$@"
  fi
}

# Fails early with a clear message if a tool is missing
require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "Required command not found: $cmd"
  done
}

# Always runs when the script exits, even after an error
cleanup() {
  local exit_code=$?
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
  if (( exit_code != 0 )); then
    error "Script failed with exit code $exit_code"
  fi
}
trap cleanup EXIT
trap 'die "Interrupted"' INT TERM

main() {
  local opt
  while getopts ":nvh" opt; do
    case "$opt" in
      n) DRY_RUN=true ;;
      v) VERBOSE=true ;;
      h) usage; exit 0 ;;
      \?) usage; die "Unknown option: -$OPTARG" ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ $# -lt 1 ]]; then
    usage
    die "Missing <name> argument"
  fi
  local name=$1

  if [[ "$DRY_RUN" == true ]]; then
    warn "Dry run: no changes will be made"
  fi

  require_cmd date mktemp
  TMP_DIR=$(mktemp -d)
  debug "Temporary directory: $TMP_DIR"

  # ---------- your logic goes here ----------
  info "Hello, $name!"
  run touch "$TMP_DIR/example.txt"
  info "Done."
}

main "$@"
