# 03 · Permissions and Ownership

Wrong permissions cause half of all "it works on my machine" deployment failures, and they are one of the most common security findings in audits.

## How permissions work

```
-rwxr-x---  1  deploy  www-data  4096  app.sh
 │└┬┘└┬┘└┬┘     │        │
 │ │  │  │      owner    group
 │ │  │  └── others: no access
 │ │  └───── group:  read + execute
 │ └──────── owner:  read + write + execute
 └────────── type: - file, d directory, l link
```

| Number | Letters | Meaning |
|---|---|---|
| 7 | `rwx` | read + write + execute |
| 6 | `rw-` | read + write |
| 5 | `r-x` | read + execute |
| 4 | `r--` | read only |
| 0 | `---` | no access |

Common modes: `755` scripts and directories · `644` config files · `600` private keys · `700` `.ssh` directory · `440` `/etc/sudoers`.

## Special bits

| Bit | Example | What it does |
|---|---|---|
| SUID | `chmod u+s` (`4755`) | Program runs as its owner (e.g. `passwd` runs as root) |
| SGID | `chmod g+s` (`2775`) | New files in a directory inherit its group: good for shared team folders |
| Sticky | `chmod +t` (`1777`) | Only a file's owner can delete it (used on `/tmp`) |

## Essential commands

| Task | Command |
|---|---|
| Change mode | `chmod 640 file` · `chmod u+x script.sh` · `chmod -R g+w dir/` |
| Change owner | `chown deploy:www-data file` · `chown -R deploy: /opt/app` |
| Show numeric mode | `stat -c '%a %U:%G %n' file` |
| Default permissions for new files | `umask` (`022` → files `644`, dirs `755`) |
| Fine-grained access (ACL) | `setfacl -m u:alice:rw file` · `getfacl file` |
| Fix SSH key permissions | `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` |

## Script: `permission-audit.sh`

Checks critical system files, world-writable files and directories, orphaned files and SUID/SGID programs. Exits with code `1` if it finds issues, so it can run in automation.

```bash
sudo ./permission-audit.sh            # whole system
sudo ./permission-audit.sh /opt/app   # one application directory
```

## Practice tasks
1. Create `/tmp/test.txt`, run `chmod 666` on it, and confirm the audit flags it.
2. Create a shared folder for a `developers` group where new files keep the group (SGID).
3. Find out why `ssh` refuses a private key with mode `644`, and fix it.
