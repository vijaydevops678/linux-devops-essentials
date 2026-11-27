# 19 · Troubleshooting Playbook

Step-by-step guides for the incidents DevOps engineers handle most often. Each one lists the symptoms, the commands to run in order, the usual causes, and which script from this repo helps. They're also the scenario questions you'll get in interviews ("the website is down, what do you do?").

**Start every incident the same way:**
```bash
sudo ./triage.sh          # collects everything into one report and lists the red flags
```
Then: **stay calm → find what changed → fix the symptom → find the root cause → write it down.**

## Contents
1. [Disk full](#1-disk-full)
2. [Server slow / high CPU](#2-server-slow--high-cpu)
3. [Out of memory / process killed](#3-out-of-memory--process-killed)
4. [Can't SSH into the server](#4-cant-ssh-into-the-server)
5. [Service won't start](#5-service-wont-start)
6. [Website down / 502 Bad Gateway](#6-website-down--502-bad-gateway)
7. [DNS not resolving](#7-dns-not-resolving)
8. [Too many open files](#8-too-many-open-files)
9. [Clock wrong / TLS errors](#9-clock-wrong--tls-errors)
10. [Server rebooted unexpectedly](#10-server-rebooted-unexpectedly)

---

## 1. Disk full
**Symptoms:** `No space left on device`, database or app crashes, logs stop, deploys fail.

```bash
df -h                                   # which filesystem is full?
df -i                                   # or out of inodes (millions of small files)?
sudo du -xh --max-depth=1 / | sort -rh | head      # which directory? repeat one level deeper
sudo lsof +L1                           # deleted files still held open by a process
```
| Usual cause | Fix |
|---|---|
| Huge or unrotated logs | Truncate safely: `sudo truncate -s 0 /var/log/app.log`; set up logrotate |
| systemd journal | `sudo journalctl --vacuum-size=500M` |
| Docker images and containers | `docker system df` then `docker system prune -af` |
| Deleted file still open | Restart the process holding it (from `lsof +L1`) |
| Old releases, backups, core dumps | `cleanup-old-files.sh` |

**Scripts:** `02-files-and-directories/find-large-files.sh`, `10-disk-and-storage/disk-alert.sh`, `10-disk-and-storage/cleanup-old-files.sh`

---

## 2. Server slow / high CPU
**Symptoms:** slow responses, timeouts, high load in monitoring.

```bash
uptime                                  # load vs nproc
top                                     # press P (CPU) and M (memory)
vmstat 1 5                              # r = run queue, wa = IO wait, st = steal, si/so = swap
iostat -xz 1 3                          # %util and await per disk
pidstat 1 5                             # which process
```
| Usual cause | Fix |
|---|---|
| One process using all CPU | Profile it (`strace -cp <PID>`), restart, scale out |
| High IO wait | Slow or overloaded disk: faster volume, fewer writes, check `iotop` |
| High steal on a cloud VM | Burstable instance out of CPU credits: change the instance type |
| Swapping | Not enough RAM: see section 3 |

**Scripts:** `14-performance/perf-snapshot.sh`, `05-processes/process-monitor.sh`

---

## 3. Out of memory / process killed
**Symptoms:** a process disappears, exit code `137`, `OOMKilled` in Kubernetes, `Killed` in the terminal.

```bash
journalctl -k | grep -iE "out of memory|killed process"    # or: dmesg -T | grep -i oom
free -h                                 # look at "available"
ps -eo pid,rss,comm --sort=-rss | head  # biggest users of RAM
cat /sys/fs/cgroup/<path>/memory.max    # container or service memory limit
```
| Usual cause | Fix |
|---|---|
| Memory leak (usage grows until killed) | Restart as a stopgap; fix the leak; set a limit so it can't take the whole server down |
| Limit too low for the workload | Raise the container / systemd limit (`MemoryMax=`) |
| Too many workers / threads | Lower the worker count to fit the RAM |
| No swap on a small VM | Add a small swap file as a buffer (not on Kubernetes nodes) |

**Scripts:** `14-performance/perf-snapshot.sh`, `15-linux-containers-internals/inspect-namespaces.sh`

---

## 4. Can't SSH into the server
**Symptoms:** `Connection timed out`, `Connection refused`, `Permission denied (publickey)`.

```bash
ssh -vvv user@server                    # from your machine: where exactly does it fail?
nc -zv server 22                        # is the port reachable at all?
```
| Message | Likely cause | Check / fix |
|---|---|---|
| `Connection timed out` | Firewall, cloud security group, wrong IP, server down | Security group / NACL allows your IP on 22; the cloud console shows the VM running |
| `Connection refused` | sshd not running or on another port | Via the cloud **serial console**: `systemctl status ssh`, `ss -ltnp \| grep ssh` |
| `Permission denied (publickey)` | Wrong key or user, bad permissions | `~/.ssh` must be `700` and `authorized_keys` `600`, owned by the user; check `/var/log/auth.log` |
| Hangs after login | Disk full, or a slow `.bashrc` | Console access; check `df -h` |
| Worked before, now refused | Banned by fail2ban | `sudo fail2ban-client status sshd` · `sudo fail2ban-client set sshd unbanip <IP>` |

**Scripts:** `08-networking/network-check.sh`, `12-security-hardening/failed-logins-report.sh`, `12-security-hardening/ssh-hardening-check.sh`

---

## 5. Service won't start
**Symptoms:** `systemctl start` fails, or the service starts and dies straight away.

```bash
systemctl status myapp                  # state and the last log lines
journalctl -u myapp -n 50 --no-pager    # full error
journalctl -u myapp -b -p err           # errors since boot
sudo -u myapp /path/to/binary           # run it by hand as the service user
```
| Usual cause | Fix |
|---|---|
| Config syntax error | Test first: `nginx -t`, `sshd -t`, `apachectl configtest` |
| Port already in use | `sudo ss -ltnp 'sport = :8080'` shows who has it |
| Permission denied | Files must be readable by the service `User=`: `namei -l /path/to/file` |
| Missing env file or variable | Check `EnvironmentFile=` / `Environment=` in `systemctl cat myapp` |
| SELinux (RHEL) | `sudo ausearch -m avc -ts recent` |
| Restart loop: "start request repeated too quickly" | Fix the cause, then `systemctl reset-failed myapp` |

**Scripts:** `06-services-systemd/service-watchdog.sh`, `13-boot-process/boot-health-check.sh`

---

## 6. Website down / 502 Bad Gateway
**Symptoms:** users get errors; monitoring alerts.

```bash
curl -sv https://example.com -o /dev/null      # what does the outside see? (DNS, TLS, status)
curl -s localhost:3000/health                  # is the app itself alive behind Nginx?
sudo tail -n 50 /var/log/nginx/error.log        # what does Nginx say?
systemctl status nginx myapp
```
| Error | Meaning | Fix |
|---|---|---|
| `502 Bad Gateway` | Nginx is up, the app isn't | Start or fix the app (section 5), check the upstream port |
| `504 Gateway Timeout` | App too slow | Check app performance and database; raise timeouts only as a last resort |
| Certificate error | Expired or wrong certificate | `ssl-expiry-check.sh example.com`, `certbot renew` |
| Can't connect at all | DNS, firewall, load balancer health check | Section 7, cloud LB target health |
| Broke right after a deploy | Bad release | Roll back first, investigate second: `deploy.sh rollback` |

**Scripts:** `16-nginx-and-tls/ssl-expiry-check.sh`, `projects/03-app-deploy-with-rollback/deploy.sh`, `08-networking/network-check.sh`

---

## 7. DNS not resolving
**Symptoms:** `Could not resolve host`, `Name or service not known`, `Temporary failure in name resolution`.

```bash
getent hosts example.com                # what the system resolver returns
dig +short example.com                  # via the configured DNS server
dig +short example.com @8.8.8.8         # via a public resolver: is it your DNS server?
cat /etc/resolv.conf                    # which servers are used
resolvectl status                       # on systemd-resolved systems (Ubuntu)
grep example.com /etc/hosts             # a local override?
```
| Usual cause | Fix |
|---|---|
| Wrong or unreachable nameserver | Fix `/etc/resolv.conf` / netplan / NetworkManager settings |
| Record missing or recently changed | Check at the DNS provider; wait for TTL; `resolvectl flush-caches` |
| Stale entry in `/etc/hosts` | Remove it |
| Outbound UDP/TCP 53 blocked | Firewall or security group rules |

**Scripts:** `08-networking/network-check.sh`

---

## 8. Too many open files
**Symptoms:** `Too many open files` / `EMFILE` in app logs; new connections fail under load.

```bash
cat /proc/<PID>/limits | grep "open files"   # the process's real limit
ls /proc/<PID>/fd | wc -l                    # how many it has open
sudo lsof -p <PID> | awk '{print $5}' | sort | uniq -c | sort -rn   # what kind (sockets? files?)
```
| Usual cause | Fix |
|---|---|
| Limit too low for a busy service | `systemctl edit myapp` → `[Service]` `LimitNOFILE=65535`, restart |
| Set in limits.conf, but the app runs under systemd | limits.conf doesn't apply to services; use `LimitNOFILE=` |
| Leak: count keeps growing | The app doesn't close files or connections; fix the code |

**Scripts:** `17-kernel-tuning-limits/kernel-limits-audit.sh`

---

## 9. Clock wrong / TLS errors
**Symptoms:** `certificate is not yet valid`, failed logins with time-based tokens, logs out of order across servers.

```bash
timedatectl                             # "System clock synchronized: yes"?
chronyc tracking                        # offset from the time servers (chrony)
sudo systemctl restart chronyd          # or: systemd-timesyncd
```
Fix: install and enable time sync (`chrony`), allow outbound NTP (UDP 123), keep servers on UTC.

---

## 10. Server rebooted unexpectedly
**Symptoms:** uptime is low, services restarted, nobody planned it.

```bash
last -x reboot shutdown | head          # when, and was it a clean shutdown?
journalctl -b -1 -e                     # the last messages before the reboot (needs persistent journal)
journalctl -b -1 -k | grep -iE "panic|oom|watchdog|error"
```
| Usual cause | Where to look |
|---|---|
| Automatic updates with auto-reboot | `/var/log/unattended-upgrades/`, `dnf-automatic` config |
| Kernel panic or hardware fault | Previous boot kernel log; cloud provider console screenshot / logs |
| Out of memory with `panic_on_oom` | `sysctl vm.panic_on_oom` |
| Cloud host maintenance | Provider events / health dashboard |
| Someone ran `reboot` | `journalctl -b -1 \| grep -i reboot`, `last` |

Make the journal survive reboots so you can investigate next time: `sudo mkdir -p /var/log/journal && sudo systemctl restart systemd-journald`.

**Scripts:** `13-boot-process/boot-health-check.sh`

---

## Script: `triage.sh`

Read-only first-minute collector: OS, load, CPU and memory, disks and inodes, top processes, failed services, errors from the last hour, kernel messages, listening ports, DNS, logins, reboots and time sync. Saves a timestamped report to attach to the ticket and prints the **red flags** with the playbook section to read.

```bash
sudo ./triage.sh                 # report in /tmp
sudo ./triage.sh -o /var/tmp     # somewhere else (use another disk if / is full!)
```

## After the incident
Write a short **postmortem**: timeline, impact, root cause, what fixed it, and what will stop it happening again (an alert, a limit, a runbook update). Blameless: focus on the system, not the person.
