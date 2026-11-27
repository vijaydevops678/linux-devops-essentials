# 04 · Users and Groups

Every service should run as its own user, every engineer should have their own account, and nobody should share root. This topic covers how Linux manages identities.

## Key files

| File | Contents |
|---|---|
| `/etc/passwd` | One line per account: `name:x:UID:GID:comment:home:shell` |
| `/etc/shadow` | Password hashes and expiry (root only) |
| `/etc/group` | Groups and their members |
| `/etc/sudoers`, `/etc/sudoers.d/` | Who may run commands as root (edit with `visudo`) |
| `/etc/login.defs` | Defaults such as `UID_MIN` and password ageing |

UID `0` is root. System/service accounts usually have UIDs below `1000`; people get `1000` and up.

## Essential commands

| Task | Command |
|---|---|
| Create a user with home directory | `sudo useradd -m -s /bin/bash alice` |
| Set a password | `sudo passwd alice` |
| Create a service account (no login) | `sudo useradd -r -s /usr/sbin/nologin myapp` |
| Add a user to a group | `sudo usermod -aG docker alice` (`-a` = append, never forget it) |
| Give sudo rights | `sudo usermod -aG sudo alice` (Debian/Ubuntu) · `wheel` (RHEL) |
| Create a group | `sudo groupadd developers` |
| Show a user's IDs and groups | `id alice` · `groups alice` |
| Switch user | `su - alice` · `sudo -iu alice` |
| Lock / unlock an account | `sudo passwd -l alice` · `sudo passwd -u alice` |
| Force a password change | `sudo chage -d 0 alice` |
| Password expiry info | `sudo chage -l alice` |
| Delete a user and their home | `sudo userdel -r alice` |
| Who is logged in / login history | `who` · `w` · `last -n 20` |

## Scripts

### `bulk-create-users.sh`: onboard a team from a CSV
Creates missing groups, creates users, sets random passwords and forces a change at first login.

```bash
sudo ./bulk-create-users.sh -n users.csv.example    # dry run first
sudo ./bulk-create-users.sh users.csv.example
```

### `user-audit.sh`: security review of accounts
Lists login accounts, extra UID-0 accounts, admin group members, empty or locked passwords and last logins. Exits with code `1` on critical findings.

```bash
sudo ./user-audit.sh
```

## Practice tasks
1. Create a `developers` group and two users in it with the CSV script, then confirm with `id`.
2. Create a service account `myapp` that cannot log in, and own `/opt/myapp` with it.
3. Give one user permission to restart only nginx with sudo: add `alice ALL=(root) /usr/bin/systemctl restart nginx` using `visudo -f /etc/sudoers.d/alice`.
