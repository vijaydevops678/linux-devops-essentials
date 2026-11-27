#!/usr/bin/env bash
#
# bash-basics-demo.sh - Runs through the core bash building blocks with live output.
#
# Read the code and the output side by side: every section is one concept.
#
# Usage: ./bash-basics-demo.sh

set -euo pipefail

section() { printf '\n=== %s ===\n' "$1"; }

section "1. Variables and quoting"
name="DevOps"
greeting="Hello, $name"        # double quotes expand variables
literal='Hello, $name'         # single quotes keep text exactly as written
echo "$greeting"
echo "$literal"

section "2. Command substitution and arithmetic"
today=$(date +%F)
cores=$(nproc)
echo "Today is $today and this machine has $cores CPU core(s)"
echo "Double the cores: $(( cores * 2 ))"

section "3. Conditionals"
file=/etc/os-release
if [[ -f "$file" ]]; then
  echo "$file exists"
else
  echo "$file is missing"
fi
if (( cores >= 2 )); then
  echo "Multi-core machine"
else
  echo "Single-core machine"
fi

section "4. Loops"
for service in nginx docker sshd; do
  echo "Checking $service..."
done
count=1
while (( count <= 3 )); do
  echo "Attempt $count"
  count=$(( count + 1 ))
done

section "5. Arrays"
servers=(web-01 web-02 db-01)
echo "First server: ${servers[0]}"
echo "All servers:  ${servers[*]}"
echo "Server count: ${#servers[@]}"

section "6. Functions and return codes"
is_port_valid() {
  local port=$1
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}
for p in 22 8080 70000 abc; do
  if is_port_valid "$p"; then
    echo "$p: valid port"
  else
    echo "$p: invalid port"
  fi
done

section "7. Exit codes"
if grep -q '^root:' /etc/passwd; then
  echo "grep found 'root', so it returned exit code 0 (success)"
fi
set +e
ls /does-not-exist >/dev/null 2>&1
rc=$?
set -e
echo "ls on a missing path returned exit code $rc (failure)"

section "8. Reading a file line by line"
while IFS=: read -r user _ uid _; do
  if (( uid == 0 )); then
    echo "User with UID 0 (full admin rights): $user"
  fi
done < /etc/passwd

section "9. String operations"
path="/var/log/nginx/access.log"
echo "File name:  ${path##*/}"
echo "Directory:  ${path%/*}"
echo "Extension:  ${path##*.}"
echo "Uppercase:  ${name^^}"
echo "Default:    ${UNDEFINED_VAR:-fallback value}"

section "10. Here-doc (multi-line text)"
cat <<EOF
Host:   $(hostname)
User:   $(id -un)
Shell:  $BASH_VERSION
EOF
