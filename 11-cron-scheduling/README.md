# 11 · Cron and Scheduling

Backups, cleanups, health checks, certificate renewals and reports all run on a schedule. Cron is the classic way to do it; systemd timers are the modern alternative.

## Cron syntax

```
┌───────── minute (0-59)
│ ┌─────── hour (0-23)
│ │ ┌───── day of month (1-31)
│ │ │ ┌─── month (1-12)
│ │ │ │ ┌─ day of week (0-7, 0 and 7 = Sunday)
│ │ │ │ │
* * * * *  command
```

| Schedule | Meaning |
|---|---|
| `*/5 * * * *` | Every 5 minutes |
| `0 * * * *` | Every hour, on the hour |
| `30 2 * * *` | Every day at 02:30 |
| `0 9 * * 1-5` | 09:00 Monday to Friday |
| `0 0 1 * *` | Midnight on the 1st of every month |
| `@reboot` | Once, at boot |

Check expressions at [crontab.guru](https://crontab.guru).

## Essential commands

| Task | Command |
|---|---|
| Edit your crontab | `crontab -e` |
| List it | `crontab -l` |
| Edit another user's crontab | `sudo crontab -u deploy -e` |
| System-wide jobs | `/etc/crontab`, `/etc/cron.d/`, `/etc/cron.daily/` |
| Did cron run my job? | `grep CRON /var/log/syslog` · `journalctl -u cron` |
| Run once at a set time | `echo "./job.sh" \| at 23:00` |
| List systemd timers | `systemctl list-timers` |

## Cron pitfalls (the reasons jobs "work by hand but not in cron")
1. **PATH is minimal.** Use absolute paths (`/usr/bin/docker`, `/usr/local/bin/backup.sh`).
2. **No output is saved.** Always end with `>> /var/log/job.log 2>&1`.
3. **Different environment.** No `.bashrc`; set variables in the script or at the top of the crontab.
4. **`%` is special** in crontab lines; escape it as `\%` (e.g. `date +\%F`).
5. **Overlapping runs.** Use `flock` (as `backup.sh` does) so a slow job doesn't start twice.

## Script: `backup.sh`

Compressed backups with a checksum, archive verification, retention cleanup, logging and a lock against overlapping runs.

```bash
sudo ./backup.sh -d /backups -k 7 -n etc /etc
sudo ./backup.sh -d /backups -k 30 -n app /opt/myapp /etc/nginx
```

Schedule it daily at 02:30:
```cron
30 2 * * * /usr/local/bin/backup.sh -d /backups -k 7 -n etc /etc >> /var/log/backup.log 2>&1
```

Restore:
```bash
cd /backups
sha256sum -c etc-20261127-023000.tar.gz.sha256      # confirm the file is intact
sudo tar -xzf etc-20261127-023000.tar.gz -C /tmp/restore
```

## Practice tasks
1. Schedule `backup.sh` every 5 minutes for a test folder, check the log, then remove the job.
2. Break a job on purpose (use a relative path) and find the error in the log.
3. Convert the cron job into a systemd service + timer (see topic 06 for an example).
4. Copy the backups to another server or S3: `rsync -az /backups/ user@backup-host:/backups/` or `aws s3 sync /backups s3://my-bucket/backups`.
