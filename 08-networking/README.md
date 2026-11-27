# 08 · Networking

"The app can't reach the database" is one of the most common DevOps tickets. Troubleshoot it layer by layer: **interface → gateway → DNS → port → application**.

## Key ideas

| Concept | In one line |
|---|---|
| IP address / CIDR | `10.0.1.15/24` = host `.15` in network `10.0.1.0` with 256 addresses |
| Private ranges | `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` |
| Gateway | The router that traffic for other networks goes through |
| DNS | Turns names into IPs; configured in `/etc/resolv.conf`, overrides in `/etc/hosts` |
| Ports | `22` SSH · `80/443` HTTP(S) · `3306` MySQL · `5432` PostgreSQL · `6379` Redis |
| TCP vs UDP | TCP is connection-based (HTTP, SSH); UDP is fire-and-forget (DNS, metrics) |

## Essential commands

| Task | Command |
|---|---|
| IP addresses | `ip -brief address` · `hostname -I` |
| Routes and gateway | `ip route` |
| Listening ports and owning process | `sudo ss -tulpn` |
| Is a remote port open? | `nc -zv db.internal 5432` · `timeout 3 bash -c '</dev/tcp/host/443'` |
| DNS lookup | `dig +short github.com` · `nslookup github.com` · `getent hosts github.com` |
| Reachability | `ping -c 4 8.8.8.8` |
| Path to a host | `traceroute github.com` · `mtr github.com` |
| HTTP test with timing | `curl -sv -o /dev/null -w '%{http_code} %{time_total}\n' https://site` |
| Only response headers | `curl -I https://site` |
| Capture traffic | `sudo tcpdump -i any port 443 -n` |
| Firewall (Ubuntu) | `sudo ufw status` · `sudo ufw allow 443/tcp` |
| Firewall (RHEL) | `sudo firewall-cmd --list-all` · `sudo firewall-cmd --add-port=443/tcp --permanent` |
| Copy files over SSH | `scp file user@host:/tmp/` · `rsync -avz dir/ user@host:/opt/` |
| SSH tunnel to a remote DB | `ssh -L 5432:localhost:5432 user@bastion` |

## Script: `network-check.sh`

Runs every layer in order: interfaces, gateway, DNS, ping, TCP ports, HTTP endpoints and listening ports, then gives a pass/fail summary. It uses `/dev/tcp`, so it works even where `nc` and `telnet` are not installed.

```bash
./network-check.sh
./network-check.sh -H db.internal -p db.internal:5432
./network-check.sh -u https://myapp.example.com/health,https://api.example.com/health
```

## Practice tasks
1. Add `127.0.0.1 myapp.local` to `/etc/hosts` and confirm the script resolves it.
2. Start `python3 -m http.server 8080` and check `-p localhost:8080 -u http://localhost:8080`.
3. Block port 8080 with the firewall and see which check fails.
