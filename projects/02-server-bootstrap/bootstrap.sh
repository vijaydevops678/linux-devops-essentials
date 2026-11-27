#!/usr/bin/env bash
#
# bootstrap.sh - Turn a fresh Ubuntu/Debian or RHEL/Rocky/Alma server into a secure baseline.
#
# Steps:
#   1. Hostname and timezone
#   2. Update packages and install essential tools
#   3. Admin user with sudo and your SSH public key
#   4. SSH hardening (no root login; no passwords once your key is installed)
#   5. Firewall: deny incoming except SSH (ufw or firewalld)
#   6. fail2ban against brute-force logins
#   7. Automatic security updates
#
# Usage:   sudo ./bootstrap.sh -u admin_user -k "ssh-ed25519 AAAA... you@laptop" [-H hostname] [-t timezone] [-p ssh_port] [-n]
# Example: sudo ./bootstrap.sh -n -u vijay -k "$(cat ~/.ssh/id_ed25519.pub)" -H web-01 -t Asia/Kolkata
#
# ALWAYS run with -n (dry run) first, and keep your current SSH session open
# until you have tested logging in again in a new terminal.

set -euo pipefail

ADMIN_USER=""
SSH_KEY=""
NEW_HOSTNAME=""
TIMEZONE=""
SSH_PORT=22
DRY_RUN=false
ESSENTIALS=(curl wget git vim htop jq unzip tree rsync ca-certificates fail2ban)

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; }

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { echo "    $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "    [dry-run] $*"
  else
    "$@"
  fi
}

# write_file <path> <mode> : content comes from stdin
write_file() {
  local path=$1 mode=$2 content
  content=$(cat)
  if [[ "$DRY_RUN" == true ]]; then
    echo "    [dry-run] write $path (mode $mode):"
    sed 's/^/      | /' <<< "$content"
  else
    printf '%s\n' "$content" > "$path"
    chmod "$mode" "$path"
  fi
}

while getopts ":u:k:H:t:p:nh" opt; do
  case "$opt" in
    u) ADMIN_USER=$OPTARG ;;
    k) SSH_KEY=$OPTARG ;;
    H) NEW_HOSTNAME=$OPTARG ;;
    t) TIMEZONE=$OPTARG ;;
    p) SSH_PORT=$OPTARG ;;
    n) DRY_RUN=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# ---------- preflight ----------
[[ -n "$ADMIN_USER" ]] || { usage; die "-u admin_user is required"; }
[[ "$ADMIN_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "Invalid username: $ADMIN_USER"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] && (( SSH_PORT > 0 && SSH_PORT < 65536 )) || die "Invalid SSH port: $SSH_PORT"
if [[ -n "$SSH_KEY" && ! "$SSH_KEY" =~ ^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com)\ [A-Za-z0-9+/=]+ ]]; then
  die "That does not look like an SSH public key (it should start with ssh-ed25519 or ssh-rsa)"
fi
if [[ "$DRY_RUN" == false && $EUID -ne 0 ]]; then
  die "Run as root (or use -n for a dry run)"
fi

OS_RELEASE=${OS_RELEASE:-/etc/os-release}   # overridable for testing
[[ -r "$OS_RELEASE" ]] || die "Cannot detect the OS ($OS_RELEASE missing)"
os_value() { awk -F= -v k="$1" '$1 == k {gsub(/"/, "", $2); print $2}' "$OS_RELEASE"; }
ID=$(os_value ID)
ID_LIKE=$(os_value ID_LIKE)
PRETTY_NAME=$(os_value PRETTY_NAME)
case " $ID $ID_LIKE " in
  *" debian "*|*" ubuntu "*) FAMILY=debian; SUDO_GROUP=sudo; SSH_SERVICE=ssh ;;
  *" rhel "*|*" fedora "*|*" centos "*) FAMILY=rhel; SUDO_GROUP=wheel; SSH_SERVICE=sshd ;;
  *) die "Unsupported OS: ${PRETTY_NAME:-$ID}. Supported: Ubuntu, Debian, RHEL, Rocky, Alma, Fedora" ;;
esac

echo "Bootstrapping ${PRETTY_NAME:-$ID} (family: $FAMILY)"
[[ "$DRY_RUN" == true ]] && echo "DRY RUN: nothing will be changed"

# ---------- 1. hostname and timezone ----------
step "1. Hostname and timezone"
if [[ -n "$NEW_HOSTNAME" ]]; then
  run hostnamectl set-hostname "$NEW_HOSTNAME"
else
  info "hostname unchanged ($(hostname))"
fi
if [[ -n "$TIMEZONE" ]]; then
  [[ -e "/usr/share/zoneinfo/$TIMEZONE" ]] || die "Unknown timezone: $TIMEZONE"
  run timedatectl set-timezone "$TIMEZONE"
else
  info "timezone unchanged"
fi

# ---------- 2. packages ----------
step "2. Update packages and install essentials"
if [[ "$FAMILY" == debian ]]; then
  export DEBIAN_FRONTEND=noninteractive
  run apt-get update -qq
  run apt-get upgrade -y -qq
  run apt-get install -y -qq "${ESSENTIALS[@]}" ufw unattended-upgrades
else
  run dnf install -y -q epel-release || true   # fail2ban comes from EPEL on RHEL-like systems
  run dnf upgrade -y -q
  run dnf install -y -q "${ESSENTIALS[@]}" firewalld dnf-automatic
fi

# ---------- 3. admin user ----------
step "3. Admin user '$ADMIN_USER'"
if id "$ADMIN_USER" >/dev/null 2>&1; then
  info "user exists"
else
  run useradd -m -s /bin/bash "$ADMIN_USER"
fi
run usermod -aG "$SUDO_GROUP" "$ADMIN_USER"

KEY_INSTALLED=false
home_dir=$(getent passwd "$ADMIN_USER" | cut -d: -f6 || true)
home_dir=${home_dir:-/home/$ADMIN_USER}
if [[ -n "$SSH_KEY" ]]; then
  run install -d -m 700 -o "$ADMIN_USER" -g "$ADMIN_USER" "$home_dir/.ssh"
  if [[ "$DRY_RUN" == true ]]; then
    echo "    [dry-run] add key to $home_dir/.ssh/authorized_keys (mode 600)"
  elif ! grep -qxF "$SSH_KEY" "$home_dir/.ssh/authorized_keys" 2>/dev/null; then
    echo "$SSH_KEY" >> "$home_dir/.ssh/authorized_keys"
  fi
  run chmod 600 "$home_dir/.ssh/authorized_keys"
  run chown "$ADMIN_USER:$ADMIN_USER" "$home_dir/.ssh/authorized_keys"
  KEY_INSTALLED=true
  info "SSH key installed for $ADMIN_USER"
elif [[ -s "$home_dir/.ssh/authorized_keys" ]]; then
  KEY_INSTALLED=true
  info "existing authorized_keys found for $ADMIN_USER"
else
  info "no SSH key given: password login will stay ENABLED so you are not locked out"
fi

# ---------- 4. SSH hardening ----------
step "4. SSH hardening"
if [[ "$KEY_INSTALLED" == true ]]; then PASSWORD_AUTH=no; else PASSWORD_AUTH=yes; fi
if grep -Eqs '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config || [[ "$DRY_RUN" == true ]]; then
  run mkdir -p /etc/ssh/sshd_config.d
  write_file /etc/ssh/sshd_config.d/99-hardening.conf 644 <<EOF
# Managed by bootstrap.sh
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication $PASSWORD_AUTH
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
  if [[ "$DRY_RUN" == false ]]; then
    sshd -t || die "sshd config test failed; fix /etc/ssh/sshd_config.d/99-hardening.conf before reloading"
  fi
  if [[ "$FAMILY" == rhel && "$SSH_PORT" != 22 ]]; then
    run semanage port -a -t ssh_port_t -p tcp "$SSH_PORT" || true   # SELinux must allow the new port
  fi
  run systemctl reload "$SSH_SERVICE"
else
  info "SKIPPED: /etc/ssh/sshd_config has no 'Include /etc/ssh/sshd_config.d/' line; add the settings by hand"
fi

# ---------- 5. firewall ----------
step "5. Firewall (allow SSH on port $SSH_PORT only)"
if [[ "$FAMILY" == debian ]]; then
  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw allow "$SSH_PORT/tcp"
  run ufw --force enable
else
  run systemctl enable --now firewalld
  run firewall-cmd --permanent --add-port="$SSH_PORT/tcp"
  run firewall-cmd --reload
fi

# ---------- 6. fail2ban ----------
step "6. fail2ban"
write_file /etc/fail2ban/jail.local 644 <<EOF
[sshd]
enabled  = true
port     = $SSH_PORT
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
run systemctl enable --now fail2ban
run systemctl restart fail2ban

# ---------- 7. automatic security updates ----------
step "7. Automatic security updates"
if [[ "$FAMILY" == debian ]]; then
  write_file /etc/apt/apt.conf.d/20auto-upgrades 644 <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
else
  run sed -i 's/^apply_updates.*/apply_updates = yes/; s/^upgrade_type.*/upgrade_type = security/' /etc/dnf/automatic.conf
  run systemctl enable --now dnf-automatic.timer
fi

# ---------- done ----------
step "Done"
info "Admin user:        $ADMIN_USER (group $SUDO_GROUP)"
info "SSH port:          $SSH_PORT, root login disabled, password login: $PASSWORD_AUTH"
info "Firewall:          incoming denied except $SSH_PORT/tcp"
info "fail2ban:          5 failures in 10 min = 1 hour ban"
echo
echo "IMPORTANT: keep this session open and test in a NEW terminal:"
echo "    ssh -p $SSH_PORT $ADMIN_USER@<server-ip>"
if [[ "$PASSWORD_AUTH" == yes ]]; then
  echo "Then add your key (ssh-copy-id) and run this script again with -k to disable passwords."
fi
