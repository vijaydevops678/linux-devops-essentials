# 10 · Disk and Storage

A full disk takes down databases, stops logging and breaks deployments. DevOps engineers need to monitor space, add storage and clean up safely.

## Key ideas

| Concept | In one line |
|---|---|
| Block device | A disk or partition: `/dev/sda1`, `/dev/nvme0n1p1`, `/dev/xvdf` (AWS EBS) |
| Filesystem | How data is organised on the device: `ext4`, `xfs` |
| Mount point | The directory where a filesystem appears, e.g. `/data` |
| `/etc/fstab` | Filesystems mounted automatically at boot |
| Inodes | One per file. You can run out of inodes with free space left (millions of tiny files) |
| LVM | Flexible volumes you can grow without repartitioning |
| Deleted-but-open files | Space isn't freed until the process holding the file restarts |

## Essential commands

| Task | Command |
|---|---|
| Space per filesystem | `df -h` · inodes: `df -i` |
| Biggest directories | `du -h --max-depth=1 /var \| sort -rh \| head` |
| List disks and partitions | `lsblk` · `sudo fdisk -l` |
| Filesystem UUIDs | `sudo blkid` |
| Format a new disk | `sudo mkfs.ext4 /dev/xvdf` |
| Mount / unmount | `sudo mount /dev/xvdf /data` · `sudo umount /data` |
| Mount at boot | add `UUID=<uuid> /data ext4 defaults,nofail 0 2` to `/etc/fstab`, then `sudo mount -a` |
| Grow a partition and filesystem | `sudo growpart /dev/xvda 1` then `sudo resize2fs /dev/xvda1` (ext4) or `sudo xfs_growfs /` |
| LVM overview | `sudo pvs` · `sudo vgs` · `sudo lvs` |
| Grow an LVM volume and its filesystem | `sudo lvextend -r -L +10G /dev/vg0/data` |
| Deleted files still using space | `sudo lsof +L1` |
| Free journal space | `sudo journalctl --vacuum-size=500M` |
| Clean Docker | `docker system prune -af` |

## Scripts

### `disk-alert.sh`: alert before a disk fills up
Checks space and inodes on every real filesystem and can post alerts to a Slack-compatible webhook. Exits with code `1` when any filesystem is over the limit.

```bash
./disk-alert.sh
./disk-alert.sh -t 85 -i 90
./disk-alert.sh -t 85 -w "https://hooks.slack.com/services/XXX/YYY/ZZZ"
```
Cron, every 15 minutes:
```cron
*/15 * * * * /usr/local/bin/disk-alert.sh -t 85 -w "https://hooks.slack.com/services/XXX" >> /var/log/disk-alert.log 2>&1
```

### `cleanup-old-files.sh`: safe cleanup of old logs and artifacts
Dry run by default. `-z` compresses, `-x` deletes. Refuses to run on system directories.

```bash
./cleanup-old-files.sh -d /var/log/myapp -a 14                  # list only
sudo ./cleanup-old-files.sh -d /var/log/myapp -a 14 -z          # gzip them
sudo ./cleanup-old-files.sh -d /tmp/builds -a 3 -p "*" -x       # delete them
```

## Practice tasks
1. Run `disk-alert.sh -t 1` to force an alert and see the output and exit code.
2. Create 20 old test files with `touch -d "30 days ago" /tmp/old/file{1..20}.log` and clean them up.
3. On a cloud VM, attach a second disk, format it, mount it on `/data`, and make the mount survive a reboot.
