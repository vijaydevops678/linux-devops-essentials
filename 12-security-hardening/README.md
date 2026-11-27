# 12 · Security Hardening

Any server with a public IP gets SSH brute-force attempts within minutes of booting. Basic hardening blocks almost all of them: keys instead of passwords, no root login, a firewall, automatic security updates and least privilege.

## Server hardening checklist

| # | Control | How |
|---|---|---|
| 1 | Log in with SSH keys, not passwords | `ssh-keygen -t ed25519` · `ssh-copy-id user@server` · `PasswordAuthentication no` |
| 2 | No direct root login | `PermitRootLogin no`; use a normal user + `sudo` |
| 3 | Firewall: deny by default | `ufw default deny incoming && ufw allow OpenSSH && ufw enable` |
| 4 | Block brute force | `apt install fail2ban` (protects SSH out of the box) |
| 5 | Automatic security updates | `apt install unattended-upgrades` · RHEL: `dnf-automatic` |
| 6 | Least privilege | Apps run as their own user; limited `sudo` rules |
| 7 | Remove what you don't use | `systemctl disable --now <service>`, remove unused packages |
| 8 | Protect secrets | `chmod 600` key files; never commit `.env` files to git |
| 9 | Audit regularly | `permission-audit.sh` (03), `user-audit.sh` (04), the scripts below |
| 10 | Keep logs and watch them | `failed-logins-report.sh`, `journalctl -p warning` |

## Essential commands

| Task | Command |
|---|---|
| Generate an SSH key | `ssh-keygen -t ed25519 -C "you@example.com"` |
| Copy your key to a server | `ssh-copy-id -i ~/.ssh/id_ed25519.pub user@server` |
| Test sshd config before reload | `sudo sshd -t && sudo systemctl reload ssh` |
| Effective sshd settings | `sudo sshd -T \| grep -i password` |
| Firewall status (Ubuntu) | `sudo ufw status verbose` |
| Allow a port | `sudo ufw allow 443/tcp` |
| Firewall (RHEL) | `sudo firewall-cmd --list-all` · `--add-service=https --permanent` then `--reload` |
| Banned IPs (fail2ban) | `sudo fail2ban-client status sshd` |
| Who used sudo | `grep sudo /var/log/auth.log` · `journalctl _COMM=sudo` |
| Open ports | `sudo ss -tulpn` |
| Pending security updates | `apt list --upgradable` · `dnf updateinfo list security` |

## Scripts

### `ssh-hardening-check.sh`: grade your SSH config
Checks root login, password auth, empty passwords, key auth, auth tries, X11, timeouts and login restrictions. Gives PASS / WARN / FAIL with the exact fix. Exits with code `1` if anything fails.

```bash
sudo ./ssh-hardening-check.sh                       # the running server
./ssh-hardening-check.sh -f sample-sshd_config      # practise on the sample file
```

### `failed-logins-report.sh`: who is attacking your SSH?
Failed attempts, attacking IPs, usernames tried, successful logins, and block commands for the worst IPs. Works with `/var/log/auth.log`, `/var/log/secure` or the journal. A [`sample-auth.log`](sample-auth.log) is included.

```bash
./failed-logins-report.sh sample-auth.log
sudo ./failed-logins-report.sh -b 5
```

## Practice tasks
1. Run the SSH check on `sample-sshd_config`, write a hardened version, and get it to pass.
2. On a test VM, set up key-only login. **Keep one session open** while you test a second login.
3. Install fail2ban, fail three logins from another machine, and find the ban with `fail2ban-client`.
