# 02 · Files and Directories

Servers fill up with logs, artifacts and old releases. Knowing the filesystem layout and how to find things fast is everyday DevOps work.

## Linux directory layout

| Path | What lives there |
|---|---|
| `/etc` | Configuration files (`nginx.conf`, `sshd_config`, `fstab`) |
| `/var/log` | Logs: the first place to look when something breaks |
| `/var/lib` | Application data (Docker images, databases) |
| `/opt` | Software installed outside the package manager |
| `/home`, `/root` | User home directories |
| `/tmp` | Temporary files, often cleared on reboot |
| `/proc`, `/sys` | Virtual files exposing kernel and process information |
| `/usr/bin`, `/usr/local/bin` | Programs; put your own scripts in `/usr/local/bin` |

## Essential commands

| Task | Command |
|---|---|
| List with details and hidden files | `ls -lah` |
| Show the directory tree | `tree -L 2 /etc/nginx` |
| Copy keeping permissions | `cp -a src/ dest/` |
| Sync directories (fast, resumable) | `rsync -avh --progress src/ dest/` |
| Move or rename | `mv old new` |
| Make nested directories | `mkdir -p /opt/app/releases` |
| Find by name | `find /etc -name "*.conf"` |
| Find files bigger than 100 MB | `find / -xdev -type f -size +100M` |
| Find files changed in the last day | `find /var/log -mtime -1` |
| Size of each subdirectory | `du -h --max-depth=1 /var \| sort -rh` |
| Free space per filesystem | `df -h` |
| Follow a growing log | `tail -f /var/log/syslog` |
| Symbolic link | `ln -sfn /opt/app/releases/v2 /opt/app/current` |
| Compress / extract | `tar -czf backup.tar.gz dir/` · `tar -xzf backup.tar.gz` |

## Script: `find-large-files.sh`

Shows filesystem usage, the biggest directories, the biggest files and the files changed in the last 24 hours.

```bash
./find-large-files.sh                       # current directory
sudo ./find-large-files.sh -n 20 /var       # top 20 under /var
sudo ./find-large-files.sh -s 1G /          # files bigger than 1 GB
```

## Practice tasks
1. Run the script on `/var` and find which directory is biggest.
2. Create a 200 MB test file with `fallocate -l 200M /tmp/big.img` and confirm the script finds it.
3. Use `find` to list all `.log` files in `/var/log` older than 7 days.
