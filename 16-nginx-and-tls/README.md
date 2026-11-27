# 16 · Nginx and TLS Certificates

Almost every web app you deploy sits behind **Nginx** as a reverse proxy, and every public endpoint needs a valid **TLS certificate**. Expired certificates are one of the most common causes of outages, and they're completely preventable.

## Nginx basics

| | Ubuntu / Debian | RHEL / Rocky |
|---|---|---|
| Install | `sudo apt install nginx` | `sudo dnf install nginx` |
| Main config | `/etc/nginx/nginx.conf` | `/etc/nginx/nginx.conf` |
| Your sites | `/etc/nginx/sites-available/` → symlink into `sites-enabled/` | `/etc/nginx/conf.d/*.conf` |
| Logs | `/var/log/nginx/access.log`, `error.log` | same |
| Default web root | `/var/www/html` | `/usr/share/nginx/html` |

| Task | Command |
|---|---|
| **Test config before reloading** | `sudo nginx -t` |
| Reload without dropping connections | `sudo systemctl reload nginx` |
| Show the full active config | `sudo nginx -T` |
| Follow errors | `sudo tail -f /var/log/nginx/error.log` |
| Allow proxying on RHEL (SELinux) | `sudo setsebool -P httpd_can_network_connect 1` |

### Reverse proxy config
[`nginx/myapp.conf`](nginx/myapp.conf) is a production-style config: HTTP→HTTPS redirect, Let's Encrypt challenge path, TLS 1.2/1.3, security headers, proxy headers (`X-Forwarded-For`, `X-Forwarded-Proto`), upstream keepalive, static files served directly, and a quiet `/health` endpoint. CI checks it with `nginx -t` and sends real HTTPS requests through it on every push.

### Common Nginx errors

| Error | Cause | Fix |
|---|---|---|
| `502 Bad Gateway` | The app behind Nginx is down or on another port | `curl localhost:3000`, check the app's service and logs |
| `504 Gateway Timeout` | The app is too slow | Fix the app, or raise `proxy_read_timeout` |
| `413 Request Entity Too Large` | Upload bigger than the limit | `client_max_body_size 50m;` |
| `bind() to 0.0.0.0:80 failed` | Something else uses port 80 | `sudo ss -ltnp 'sport = :80'` |
| `key values mismatch` | Certificate and key don't belong together | `./cert-tool.sh match cert.pem key.pem` |
| `permission denied` connecting upstream (RHEL) | SELinux | `setsebool -P httpd_can_network_connect 1` |

## TLS essentials

| Term | Meaning |
|---|---|
| Certificate | Public key + identity (domain names), signed by a CA |
| Private key | Secret half; never leaves the server (`chmod 600`) |
| CA / chain | Your certificate → intermediate → root. Servers must send the intermediate too (`fullchain.pem`) |
| SAN | The domain names the certificate covers; browsers only check SAN, not CN |
| Let's Encrypt | Free CA, 90-day certificates, renewed automatically by certbot |

### Let's Encrypt with certbot

```bash
sudo apt install certbot python3-certbot-nginx      # RHEL: sudo dnf install certbot python3-certbot-nginx
sudo certbot --nginx -d example.com -d www.example.com   # gets the certificate and edits the Nginx config
sudo certbot renew --dry-run                         # test automatic renewal
systemctl list-timers | grep certbot                 # renewal runs twice a day
```

### openssl commands worth knowing

| Task | Command |
|---|---|
| What certificate does a server send? | `openssl s_client -connect example.com:443 -servername example.com </dev/null \| openssl x509 -noout -subject -issuer -dates` |
| Read a certificate file | `openssl x509 -in cert.pem -noout -text` |
| Expiry date only | `openssl x509 -in cert.pem -noout -enddate` |
| Does it expire within 30 days? | `openssl x509 -in cert.pem -noout -checkend 2592000` |
| Test a specific TLS version | `openssl s_client -connect host:443 -tls1_2` |
| Convert to PFX (Windows/Azure) | `openssl pkcs12 -export -in cert.pem -inkey key.pem -out cert.pfx` |

## Scripts

### `ssl-expiry-check.sh`: monitor certificate expiry
Checks websites (`host` or `host:port`) and local certificate files: days left, issuer, whether the hostname is covered (wildcards included), self-signed detection. Grades OK / WARN / CRIT, exits `0`/`1`/`2`, optional Slack webhook.

```bash
./ssl-expiry-check.sh github.com example.com
./ssl-expiry-check.sh -w 30 -c 7 -f domains.txt          # one domain per line, # comments allowed
./ssl-expiry-check.sh /etc/letsencrypt/live/example.com/fullchain.pem
```
Daily cron with alerts:
```cron
0 8 * * * /usr/local/bin/ssl-expiry-check.sh -f /etc/ssl-domains.txt -W "https://hooks.slack.com/services/XXX" >/dev/null 2>&1
```

### `cert-tool.sh`: openssl tasks without remembering the flags

```bash
./cert-tool.sh selfsigned myapp.local 365     # dev/internal certificate + key
./cert-tool.sh csr api.example.com            # key + CSR to send to a CA
./cert-tool.sh inspect github.com             # or a .crt / .csr file
./cert-tool.sh match server.crt server.key    # do they belong together?
./cert-tool.sh chain example.com              # is the intermediate certificate sent?
```

## Practice tasks
1. Create a self-signed certificate for `myapp.local` and serve it with `openssl s_server -accept 8443 -cert myapp.local.crt -key myapp.local.key -www`, then check it with both scripts.
2. Install Nginx, run any app on port 3000 (`python3 -m http.server 3000`), and put it behind `nginx/myapp.conf` with your self-signed certificate.
3. Check five websites you use with `ssl-expiry-check.sh` and find which CA each one uses.
