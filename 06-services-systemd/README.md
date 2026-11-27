# 06 · Services and systemd

On almost every modern Linux server, **systemd** starts, stops, restarts and logs your services. Turning an app into a systemd service is how you make it start on boot and recover from crashes.

## Essential commands

| Task | Command |
|---|---|
| Status, recent logs | `systemctl status nginx` |
| Start / stop / restart | `sudo systemctl start\|stop\|restart nginx` |
| Reload config without downtime | `sudo systemctl reload nginx` |
| Start on boot (and now) | `sudo systemctl enable --now nginx` |
| Disable on boot | `sudo systemctl disable nginx` |
| Is it running? (for scripts) | `systemctl is-active --quiet nginx && echo up` |
| All failed units | `systemctl --failed` |
| List running services | `systemctl list-units --type=service --state=running` |
| After editing a unit file | `sudo systemctl daemon-reload` |
| Show a unit's file | `systemctl cat nginx` |
| Logs of a service | `journalctl -u nginx` · `-f` follow · `-n 50` last lines |
| Logs since a time | `journalctl -u nginx --since "1 hour ago"` |
| Errors only, this boot | `journalctl -p err -b` |
| Timers | `systemctl list-timers` |

## Unit file anatomy

See [`myapp.service`](myapp.service). The important lines:

| Line | Meaning |
|---|---|
| `After=network-online.target` | Start after the network is up |
| `User=myapp` | Never run apps as root |
| `WorkingDirectory=` / `ExecStart=` | Where and what to run (use absolute paths) |
| `EnvironmentFile=-/path/.env` | Load settings; `-` means "ignore if missing" |
| `Restart=on-failure` + `RestartSec=5` | Auto-restart after a crash |
| `WantedBy=multi-user.target` | Start on normal boot when enabled |

## Script: `service-watchdog.sh`

Checks services and restarts any that are down, then confirms they recovered and shows their last log lines if not. Use `-c` to only check.

```bash
sudo ./service-watchdog.sh nginx docker ssh
./service-watchdog.sh -c nginx               # check only, no root needed
```

Run it automatically every 5 minutes with the included [`service-watchdog.service`](service-watchdog.service) and [`service-watchdog.timer`](service-watchdog.timer). The install steps are at the top of each file.

## Practice tasks
1. Install nginx, stop it, and watch the watchdog bring it back.
2. Turn a simple script (for example `python3 -m http.server 8080`) into a service using `myapp.service` as a template.
3. Kill your service's process with `kill -9` and confirm `Restart=on-failure` restarts it.
