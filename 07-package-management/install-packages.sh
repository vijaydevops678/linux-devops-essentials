#!/usr/bin/env bash
#
# install-packages.sh - Install packages on any major Linux distribution.
#
# Detects the package manager (apt, dnf, yum, zypper, apk, pacman), refreshes
# the package index, skips anything already installed and reports what
# happened. With no package names it installs a standard DevOps toolkit.
#
# Usage:   sudo ./install-packages.sh [-n] [-u] [package ...]
# Example: sudo ./install-packages.sh -n            (dry run of the default toolkit)
#          sudo ./install-packages.sh nginx docker.io

set -euo pipefail

DEFAULT_PACKAGES=(curl wget git vim htop jq unzip tree tmux rsync)
DRY_RUN=false
UPGRADE=false
INSTALLED=()
SKIPPED=()
FAILED=()

usage() {
  cat <<EOF
Usage: ${0##*/} [-n] [-u] [package ...]

  -n   Dry run: show the commands without running them
  -u   Also upgrade all installed packages
  -h   Show this help

Default packages: ${DEFAULT_PACKAGES[*]}
EOF
}

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

detect_pm() {
  local pm
  for pm in apt-get dnf yum zypper apk pacman; do
    if command -v "$pm" >/dev/null 2>&1; then
      echo "$pm"
      return 0
    fi
  done
  return 1
}

is_installed() {
  case "$PM" in
    apt-get)        dpkg -s "$1" >/dev/null 2>&1 ;;
    dnf|yum|zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    apk)            apk info -e "$1" >/dev/null 2>&1 ;;
    pacman)         pacman -Qi "$1" >/dev/null 2>&1 ;;
  esac
}

refresh_index() {
  case "$PM" in
    apt-get) run apt-get update -qq ;;
    dnf|yum) run "$PM" makecache -q ;;
    zypper)  run zypper --quiet refresh ;;
    apk)     run apk update ;;
    pacman)  run pacman -Sy --noconfirm ;;
  esac
}

install_pkg() {
  case "$PM" in
    apt-get) run apt-get install -y -qq "$1" ;;
    dnf|yum) run "$PM" install -y -q "$1" ;;
    zypper)  run zypper --non-interactive install "$1" ;;
    apk)     run apk add "$1" ;;
    pacman)  run pacman -S --noconfirm --needed "$1" ;;
  esac
}

upgrade_all() {
  case "$PM" in
    apt-get) run apt-get upgrade -y -qq ;;
    dnf)     run dnf upgrade -y -q ;;
    yum)     run yum update -y -q ;;
    zypper)  run zypper --non-interactive update ;;
    apk)     run apk upgrade ;;
    pacman)  run pacman -Syu --noconfirm ;;
  esac
}

while getopts ":nuh" opt; do
  case "$opt" in
    n) DRY_RUN=true ;;
    u) UPGRADE=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [[ "$DRY_RUN" == false && $EUID -ne 0 ]]; then
  echo "Run as root (or use -n for a dry run)" >&2
  exit 1
fi

PM=$(detect_pm) || { echo "No supported package manager found" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive

if [[ $# -gt 0 ]]; then
  PACKAGES=("$@")
else
  PACKAGES=("${DEFAULT_PACKAGES[@]}")
fi

echo "Package manager: $PM"
echo "Refreshing package index..."
refresh_index

if [[ "$UPGRADE" == true ]]; then
  echo "Upgrading installed packages..."
  upgrade_all
fi

for pkg in "${PACKAGES[@]}"; do
  if is_installed "$pkg"; then
    echo "  = $pkg already installed"
    SKIPPED+=("$pkg")
  elif install_pkg "$pkg"; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "  + $pkg would be installed"
    else
      echo "  + $pkg installed"
    fi
    INSTALLED+=("$pkg")
  else
    echo "  ! $pkg failed"
    FAILED+=("$pkg")
  fi
done

echo
label="Installed"
[[ "$DRY_RUN" == true ]] && label="To install"
echo "$label: ${#INSTALLED[@]}  Already present: ${#SKIPPED[@]}  Failed: ${#FAILED[@]}"
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "Failed packages: ${FAILED[*]} (check the name for this distribution)"
  exit 1
fi
