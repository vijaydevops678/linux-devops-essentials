#!/usr/bin/env bash
#
# install-dotfiles.sh - Add the DevOps shell setup to ~/.bashrc safely (and remove it again).
#
# Copies dotfiles/devops.bashrc to ~/.config/devops-shell/ and adds one
# clearly marked block to ~/.bashrc that loads it. Backs up ~/.bashrc first,
# never adds the block twice, and -u removes it cleanly.
#
# Usage:   ./install-dotfiles.sh [-n] [-u]
#   -n  dry run: show what would change
#   -u  uninstall
# After installing: source ~/.bashrc  (or open a new terminal)

set -euo pipefail

DRY_RUN=false
UNINSTALL=false
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dotfiles/devops.bashrc"
DEST_DIR="$HOME/.config/devops-shell"
DEST="$DEST_DIR/devops.bashrc"
BASHRC="$HOME/.bashrc"
BEGIN="# >>> devops-shell >>>"
END="# <<< devops-shell <<<"

usage() { sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'; }

while getopts ":nuh" opt; do
  case "$opt" in
    n) DRY_RUN=true ;;
    u) UNINSTALL=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

backup() {
  if [[ -f "$BASHRC" ]]; then
    local copy
    copy="$BASHRC.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$BASHRC" "$copy"
    echo "Backed up $BASHRC to $copy"
  fi
}

if [[ "$UNINSTALL" == true ]]; then
  if [[ -f "$BASHRC" ]] && grep -qF "$BEGIN" "$BASHRC"; then
    if [[ "$DRY_RUN" == true ]]; then
      echo "[dry-run] remove the devops-shell block from $BASHRC and delete $DEST_DIR"
      exit 0
    fi
    backup
    sed -i "/^$BEGIN\$/,/^$END\$/d" "$BASHRC"
    rm -rf -- "$DEST_DIR"
    echo "Removed. Open a new terminal to get your old shell back."
  else
    echo "Not installed: nothing to remove."
  fi
  exit 0
fi

[[ -f "$SRC" ]] || { echo "Missing $SRC" >&2; exit 1; }

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] copy $SRC -> $DEST"
  if grep -qsF "$BEGIN" "$BASHRC"; then
    echo "[dry-run] $BASHRC already loads it: no change"
  else
    echo "[dry-run] append to $BASHRC:"
    printf '  %s\n' "$BEGIN" "[ -f \"$DEST\" ] && . \"$DEST\"" "$END"
  fi
  exit 0
fi

mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST"
echo "Installed $DEST"

if grep -qsF "$BEGIN" "$BASHRC"; then
  echo "$BASHRC already loads it: updated the file only."
else
  backup
  {
    echo ""
    echo "$BEGIN"
    echo "[ -f \"$DEST\" ] && . \"$DEST\""
    echo "$END"
  } >> "$BASHRC"
  echo "Added a loader block to $BASHRC"
fi
echo "Run: source ~/.bashrc   (or open a new terminal)"
