# Project 1 · Server Health Monitor

A single bash script that checks a server's health, grades every metric **OK / WARN / CRIT**, keeps a history log and sends an alert to Slack (or any compatible webhook) when something is wrong. It's the kind of monitoring you set up on day one, before Prometheus exists.

## What it checks

| Check | Source | Default WARN / CRIT |
|---|---|---|
| CPU usage | Two samples of `/proc/stat`, one second apart | 80% / 95% |
| Load average (5 min, per core) | `/proc/loadavg` ÷ `nproc` | 1.0 / 2.0 |
| Memory | `MemAvailable` in `/proc/meminfo` | 80% / 95% |
| Swap | `/proc/meminfo` | 50% / 80% |
| Every real disk | `df -P` (skips tmpfs, overlay, squashfs) | 80% / 90% |
| Zombie processes | `ps` | 1 / 10 |
| Failed systemd services | `systemctl --failed` | any = CRIT |

Plus the top 5 processes by CPU and by memory, so you can see the cause straight away.

## Linux skills used
`/proc` filesystem · `awk` arithmetic · `df` / `ps` / `systemctl` · functions and arrays · exit codes · environment variables · `curl` webhooks · cron

## Usage

```bash
./health-check.sh                                   # full report
./health-check.sh -q -l /var/log/health-check.log   # one-line summary + log history
./health-check.sh -w "https://hooks.slack.com/services/XXX/YYY/ZZZ"
CPU_WARN=70 DISK_CRIT=85 ./health-check.sh          # custom thresholds
```

Exit codes follow the Nagios convention (`0` OK, `1` WARNING, `2` CRITICAL), so Nagios, Zabbix, Icinga or a CI job can use the script directly.

## Example output

```
Server health report: web-01 - 2026-11-27 17:02:02
  OS: Ubuntu 24.04.5 LTS | Kernel: 6.8.0-48-generic | Uptime: up 3 days, 4 hours | CPU cores: 2

Checks:
  OK    CPU usage                12.5%
  OK    Load (5 min)             0.42 / 0.35 / 0.30 (0.17 per core)
  WARN  Memory                   83.1% used (6668 MB of 8023 MB)
  INFO  Swap                     not configured
  OK    Disk /                   61% used
  CRIT  Disk /var/lib/docker     93% used
  OK    Zombie processes         0
  OK    Failed services          0

Overall status: CRITICAL
```

## Run it every 5 minutes

```bash
sudo cp health-check.sh /usr/local/bin/
sudo crontab -e
```
```cron
*/5 * * * * /usr/local/bin/health-check.sh -q -l /var/log/health-check.log -w "https://hooks.slack.com/services/XXX" >/dev/null 2>&1
```

Get a Slack webhook URL: Slack → Apps → *Incoming Webhooks* → Add to a channel.

## Ideas to extend it
- Add an HTTP check for your app's `/health` endpoint
- Check SSL certificate expiry with `openssl s_client`
- Write an HTML report and serve it with nginx
- Send the metrics to Prometheus with the node_exporter textfile collector
