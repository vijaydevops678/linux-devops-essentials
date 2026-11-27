#!/usr/bin/env bash
#
# bulk-create-users.sh - Create many Linux users from a CSV file.
#
# CSV format (one user per line, lines starting with # are ignored):
#   username,groups,shell
#   alice,developers;docker,/bin/bash
#
# For each user it creates missing groups, creates the user with a home
# directory, sets a random password and forces a password change at first
# login. Passwords are saved to a file only root can read.
#
# Usage:   sudo ./bulk-create-users.sh [-n] [-o credentials_file] users.csv
# Example: sudo ./bulk-create-users.sh -n users.csv.example     (dry run)

set -euo pipefail

DRY_RUN=false
CRED_FILE="./new-users-credentials.txt"
CREATED=0
SKIPPED=0
declare -A NEW_GROUPS=()   # groups created (or planned in dry run) by this run

usage() {
  cat <<EOF
Usage: ${0##*/} [-n] [-o credentials_file] users.csv

  -n       Dry run: show what would be created
  -o file  Where to save the generated passwords (default: $CRED_FILE)
  -h       Show this help
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

gen_password() {
  local raw
  raw=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')
  printf '%s' "${raw:0:16}"
}

while getopts ":no:h" opt; do
  case "$opt" in
    n) DRY_RUN=true ;;
    o) CRED_FILE=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

CSV=${1:-}
[[ -n "$CSV" ]] || { usage; exit 1; }
[[ -f "$CSV" ]] || die "File not found: $CSV"
if [[ "$DRY_RUN" == false && $EUID -ne 0 ]]; then
  die "Run as root (or use -n for a dry run)"
fi

if [[ "$DRY_RUN" == false ]]; then
  : > "$CRED_FILE"
  chmod 600 "$CRED_FILE"
fi

line_no=0
while IFS=, read -r username groups shell || [[ -n "${username:-}" ]]; do
  line_no=$((line_no + 1))
  username=${username//[[:space:]]/}
  groups=${groups//[[:space:]]/}
  shell=${shell//[[:space:]]/}

  [[ -z "$username" || "$username" == \#* ]] && continue

  if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "Line $line_no: invalid username '$username', skipped"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  if id "$username" >/dev/null 2>&1; then
    echo "User $username already exists, skipped"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  shell=${shell:-/bin/bash}
  echo "Creating user $username (groups: ${groups:-none}, shell: $shell)"

  # Create any missing groups
  if [[ -n "$groups" ]]; then
    IFS=';' read -ra group_list <<< "$groups"
    for g in "${group_list[@]}"; do
      if [[ -z "${NEW_GROUPS[$g]:-}" ]] && ! getent group "$g" >/dev/null; then
        run groupadd "$g"
        NEW_GROUPS[$g]=1
      fi
    done
  fi

  args=(-m -s "$shell")
  if [[ -n "$groups" ]]; then
    args+=(-G "${groups//;/,}")
  fi
  run useradd "${args[@]}" "$username"

  password=$(gen_password)
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [dry-run] set a random password and force a change at first login"
  else
    printf '%s:%s\n' "$username" "$password" | chpasswd
    chage -d 0 "$username"
    printf '%s:%s\n' "$username" "$password" >> "$CRED_FILE"
  fi
  CREATED=$((CREATED + 1))
done < "$CSV"

echo
echo "Created: $CREATED   Skipped: $SKIPPED"
if [[ "$DRY_RUN" == false && $CREATED -gt 0 ]]; then
  echo "Passwords saved to $CRED_FILE (mode 600). Share them securely, then delete the file."
fi
