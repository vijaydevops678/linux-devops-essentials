#!/usr/bin/env bash
#
# path-doctor.sh - Explain "command not found" and "why is the wrong version running?".
#
# Checks every PATH entry in order: missing directories, duplicates, empty or
# relative entries (a security risk), and directories anyone can write to
# (someone could plant a fake 'ls' there). With -c it shows every copy of a
# command on PATH and which one wins. Also lists your shell startup files.
#
# Usage:   ./path-doctor.sh [-c command[,command...]]
# Example: ./path-doctor.sh -c python3,terraform
# Exit code: 0 = PATH is clean, 1 = problems found

set -euo pipefail

COMMANDS=""
PROBLEMS=0

usage() { sed -n '3,13p' "$0" | sed 's/^# \{0,1\}//'; }

while getopts ":c:h" opt; do
  case "$opt" in
    c) COMMANDS=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

header() { printf '\n== %s ==\n' "$1"; }

header "PATH entries (searched in this order)"
declare -A seen=()
i=0
# Split on ":" keeping empty entries (an empty entry means "current directory").
# The extra ":" at the end makes read keep a trailing empty entry.
IFS=: read -ra entries <<< "${PATH}:"
for dir in "${entries[@]}"; do
  i=$((i + 1))
  status="OK"
  if [[ -z "$dir" ]]; then
    status="PROBLEM: empty entry = current directory (remove the extra ':')"
  elif [[ "$dir" != /* ]]; then
    status="PROBLEM: relative path, depends on where you are"
  elif [[ -n "${seen[$dir]:-}" ]]; then
    status="duplicate of entry ${seen[$dir]} (harmless, but tidy it up)"
  elif [[ ! -d "$dir" ]]; then
    status="missing directory"
  elif [[ -n "$(find -L "$dir" -maxdepth 0 -perm -0002 ! -perm -1000 2>/dev/null)" ]]; then   # -L: follow symlinks like /bin -> /usr/bin
    status="PROBLEM: world-writable, anyone could put a fake command here"
  fi
  [[ -n "$dir" && -z "${seen[$dir]:-}" ]] && seen[$dir]=$i
  [[ "$status" == PROBLEM* ]] && PROBLEMS=$((PROBLEMS + 1))
  printf '  %2d  %-34s %s\n' "$i" "${dir:-<empty>}" "$status"
done

if [[ -n "$COMMANDS" ]]; then
  IFS=, read -ra cmds <<< "$COMMANDS"
  for cmd in "${cmds[@]}"; do
    header "Where is '$cmd'?"
    mapfile -t found < <(type -ap "$cmd" 2>/dev/null || true)
    if (( ${#found[@]} == 0 )); then
      echo "  not found on PATH. Install it, or add its directory to PATH, e.g.:"
      echo "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
      continue
    fi
    n=0
    for f in "${found[@]}"; do
      n=$((n + 1))
      target=$(readlink -f "$f")
      label=""; [[ $n -eq 1 ]] && label="  <- this one runs"
      if [[ "$target" != "$f" ]]; then
        echo "  $f -> $target$label"
      else
        echo "  $f$label"
      fi
    done
    (( ${#found[@]} > 1 )) && echo "  Several copies: the first one on PATH wins. Use the full path or reorder PATH."
    echo "  Tip: in your interactive shell also run 'type $cmd' to spot aliases and functions."
  done
fi

header "Your shell startup files"
printf '  %-22s %-8s %s\n' FILE EXISTS "READ BY"
for f in /etc/profile /etc/bash.bashrc /etc/bashrc "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile" "$HOME/.bashrc"; do
  case "$f" in
    /etc/profile)          who="login shells (all users)" ;;
    /etc/bash.bashrc|/etc/bashrc) who="interactive shells (all users)" ;;
    "$HOME/.bashrc")       who="interactive non-login shells (new terminal tabs)" ;;
    *)                     who="login shells (SSH): only the first that exists of .bash_profile, .bash_login, .profile" ;;
  esac
  if [[ -e "$f" ]]; then e=yes; else e=no; fi
  printf '  %-22s %-8s %s\n' "${f/#$HOME/\~}" "$e" "$who"
done
if [[ -d /etc/profile.d ]]; then
  echo "  /etc/profile.d/*.sh: $(find /etc/profile.d -maxdepth 1 -name '*.sh' | wc -l) file(s), loaded by /etc/profile"
fi

header "Summary"
if (( PROBLEMS == 0 )); then
  echo "  PATH looks clean."
  exit 0
fi
echo "  $PROBLEMS problem(s). Fix PATH where it is set (usually ~/.bashrc or ~/.profile)."
exit 1
