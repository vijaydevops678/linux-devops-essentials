# 09 · Text Processing and Logs

Logs are how you find out what went wrong. `grep`, `awk`, `sed`, `sort` and `uniq` let you answer questions like "which IP is hammering us?" or "which endpoint is throwing 500s?" in seconds, on any server, without extra tools.

## Where logs live

| Log | Path |
|---|---|
| System messages | `/var/log/syslog` (Ubuntu) · `/var/log/messages` (RHEL) · `journalctl` |
| Logins and sudo | `/var/log/auth.log` (Ubuntu) · `/var/log/secure` (RHEL) |
| Nginx | `/var/log/nginx/access.log`, `/var/log/nginx/error.log` |
| Kernel | `dmesg -T` · `journalctl -k` |
| Rotation config | `/etc/logrotate.conf`, `/etc/logrotate.d/` |

## The text toolkit

| Tool | Use it to | Example |
|---|---|---|
| `grep` | Find lines | `grep -i "error" app.log` · `-v` invert · `-c` count · `-E` regex · `-r` recursive |
| `awk` | Pick columns, do math | `awk '{print $1}' access.log` · `awk '$9 >= 500' access.log` |
| `sed` | Edit text in a stream | `sed 's/http:/https:/g' file` · `sed -i.bak 's/old/new/' config` |
| `cut` | Split by a delimiter | `cut -d: -f1 /etc/passwd` |
| `sort` / `uniq` | Count and rank | `sort \| uniq -c \| sort -rn \| head` |
| `wc` | Count lines | `wc -l access.log` |
| `tr` | Translate characters | `tr '[:lower:]' '[:upper:]'` |
| `head` / `tail` | Start / end of a file | `tail -n 100 -f app.log` |
| `xargs` | Turn output into arguments | `find . -name "*.tmp" \| xargs rm` |
| `jq` | Query JSON logs | `jq -r '.level' app.json` |
| `zcat` / `zgrep` | Read rotated `.gz` logs | `zgrep "500" access.log.2.gz` |

**The most useful one-liner in DevOps:** count anything, rank it.
```bash
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head    # top IPs
```

## Script: `log-analyzer.sh`

Turns an Nginx or Apache access log (plain or `.gz`) into a report: totals, status codes, error rates, top IPs, top URLs, failing URLs, requests per hour, user agents and suspicious requests. A realistic [`sample-access.log`](sample-access.log) is included so you can try it right away.

```bash
./log-analyzer.sh sample-access.log
./log-analyzer.sh -n 5 sample-access.log
sudo ./log-analyzer.sh /var/log/nginx/access.log /var/log/nginx/access.log.*.gz
```

## Practice tasks
1. Using only `awk`, find the total bytes sent to `203.0.113.7` in the sample log.
2. With `grep` and `wc`, count how many requests in the sample log came from `kube-probe`.
3. Write a `sed` command that masks the last part of every IP (`203.0.113.7` → `203.0.113.x`).
4. Set up `logrotate` for `/opt/myapp/logs/*.log`: daily, keep 7, compress.
