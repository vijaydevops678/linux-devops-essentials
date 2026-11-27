# Project 2 · Server Bootstrap

Turns a brand-new cloud VM into a secure baseline in one command: the first thing you run on every new Ubuntu, Debian, RHEL, Rocky or Alma server. It's the bash version of what Ansible, cloud-init and Terraform `user_data` do later in your career.

## What it does

| Step | Ubuntu / Debian | RHEL / Rocky / Alma |
|---|---|---|
| 1. Hostname, timezone | `hostnamectl`, `timedatectl` | same |
| 2. Packages | `apt-get upgrade` + essentials | `dnf upgrade` + EPEL + essentials |
| 3. Admin user | user in `sudo` group + your SSH key | user in `wheel` group + your SSH key |
| 4. SSH hardening | `/etc/ssh/sshd_config.d/99-hardening.conf`, tested with `sshd -t` | same, plus SELinux port label |
| 5. Firewall | `ufw`: deny incoming, allow SSH | `firewalld`: allow SSH port |
| 6. Brute-force protection | `fail2ban`: 5 failures = 1 hour ban | same |
| 7. Automatic security updates | `unattended-upgrades` | `dnf-automatic` (security only) |

## Safety built in
- **Dry run** with `-n` shows every command and every file before anything changes.
- **No lockout:** password login is only disabled when an SSH key is installed for the admin user.
- **Config tested** with `sshd -t` before SSH is reloaded.
- **Idempotent:** safe to run again; existing users and keys are not duplicated.

## Linux skills used
OS detection from `/etc/os-release` · user and group management · SSH key permissions · `sshd_config.d` drop-ins · `ufw` / `firewalld` · systemd · package managers · here-docs · dry-run pattern

## Usage

```bash
# 1. From your laptop: copy the script to the new server
scp bootstrap.sh root@<server-ip>:/root/

# 2. On the server: dry run first
sudo ./bootstrap.sh -n -u vijay -k "ssh-ed25519 AAAA... vijay@laptop" -H web-01 -t Asia/Kolkata

# 3. Run it for real
sudo ./bootstrap.sh -u vijay -k "ssh-ed25519 AAAA... vijay@laptop" -H web-01 -t Asia/Kolkata

# 4. In a NEW terminal (keep the old one open), test:
ssh vijay@<server-ip>
```

| Option | Meaning |
|---|---|
| `-u user` | Admin user to create (required) |
| `-k "key"` | Your SSH public key (`cat ~/.ssh/id_ed25519.pub`) |
| `-H name` | New hostname |
| `-t zone` | Timezone, e.g. `Asia/Kolkata`, `UTC` |
| `-p port` | SSH port (default 22) |
| `-n` | Dry run |

## Try it safely
Use a throwaway VM (VirtualBox, Multipass: `multipass launch --name test`, or a free-tier cloud instance). Don't experiment on a server you can't rebuild.

## Ideas to extend it
- Install Docker and add the admin user to the `docker` group
- Add a swap file if the server has none
- Turn the same steps into an Ansible playbook and compare
