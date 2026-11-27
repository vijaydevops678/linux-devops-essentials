# 🐧 Linux for DevOps: Essentials, Scripts and Projects

[![CI](https://github.com/vijaydevops678/linux-devops-essentials/actions/workflows/ci.yml/badge.svg)](https://github.com/vijaydevops678/linux-devops-essentials/actions/workflows/ci.yml)
![Bash](https://img.shields.io/badge/Bash-5.x-4EAA25?logo=gnubash&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-supported-E95420?logo=ubuntu&logoColor=white)
![RHEL](https://img.shields.io/badge/RHEL%20%2F%20Rocky-supported-EE0000?logo=redhat&logoColor=white)

The Linux skills every DevOps engineer uses daily, organised **topic by topic**: from shell basics to container internals, TLS and incident troubleshooting. Each topic has the essential commands and **real, tested bash scripts** that solve everyday operations problems. Three projects at the end combine everything.

Every script is checked by **ShellCheck** and **smoke-tested in GitHub Actions** on every push.

## 📚 Topics

| # | Topic | You'll learn | Scripts |
|---|---|---|---|
| 01 | [Shell scripting basics](01-shell-scripting-basics/) | Variables, conditionals, loops, functions, exit codes, `getopts`, `trap` | `script-template.sh` · `bash-basics-demo.sh` |
| 02 | [Files and directories](02-files-and-directories/) | Filesystem layout, `find`, `du`, `rsync`, links | `find-large-files.sh` |
| 03 | [Permissions](03-permissions/) | `chmod`, `chown`, SUID/SGID/sticky, ACLs | `permission-audit.sh` |
| 04 | [Users and groups](04-users-and-groups/) | `useradd`, `usermod`, sudo, `/etc/passwd`, `/etc/shadow` | `bulk-create-users.sh` · `user-audit.sh` |
| 05 | [Processes](05-processes/) | `ps`, `top`, signals, load average, zombies | `process-monitor.sh` |
| 06 | [Services and systemd](06-services-systemd/) | `systemctl`, `journalctl`, unit files, timers | `service-watchdog.sh` + unit files |
| 07 | [Package management](07-package-management/) | `apt` vs `dnf`, repos, version pinning | `install-packages.sh` |
| 08 | [Networking](08-networking/) | IPs, DNS, ports, `ss`, `curl`, firewalls | `network-check.sh` |
| 09 | [Text processing and logs](09-text-processing-logs/) | `grep`, `awk`, `sed`, `sort \| uniq -c`, logrotate | `log-analyzer.sh` + sample log |
| 10 | [Disk and storage](10-disk-and-storage/) | `df`, `lsblk`, mounting, `fstab`, LVM, inodes | `disk-alert.sh` · `cleanup-old-files.sh` |
| 11 | [Cron and scheduling](11-cron-scheduling/) | Cron syntax, pitfalls, `flock`, systemd timers | `backup.sh` |
| 12 | [Security hardening](12-security-hardening/) | SSH keys, sshd config, firewall, fail2ban | `ssh-hardening-check.sh` · `failed-logins-report.sh` |
| 13 | [Boot process and recovery](13-boot-process/) | GRUB, systemd targets, emergency mode, fstab mistakes | `boot-health-check.sh` + sample fstab |
| 14 | [Performance troubleshooting](14-performance/) | USE method, `vmstat`, `iostat`, iowait, steal, OOM killer | `perf-snapshot.sh` |
| 15 | [Linux behind containers](15-linux-containers-internals/) | Namespaces, cgroups v2, overlayfs, `unshare`, `nsenter` | `mini-container.sh` · `inspect-namespaces.sh` |
| 16 | [Nginx and TLS certificates](16-nginx-and-tls/) | Reverse proxy, Let's Encrypt, `openssl`, certificate chains | `ssl-expiry-check.sh` · `cert-tool.sh` + Nginx config |
| 17 | [Kernel tuning and limits](17-kernel-tuning-limits/) | `sysctl`, `ulimit`, "Too many open files", Kubernetes prerequisites | `kernel-limits-audit.sh` + sysctl file |
| 18 | [Environment and shell setup](18-environment-and-shell/) | Variables, `PATH`, startup files, sudo/cron/systemd environments | `install-dotfiles.sh` · `path-doctor.sh` + dotfiles |
| 19 | [Troubleshooting playbook](19-troubleshooting-playbook/) | 10 incident scenarios: disk full, OOM, SSH, 502, DNS, reboots... | `triage.sh` |

## 🚀 Projects

| Project | What it does | Skills combined |
|---|---|---|
| [01 · Server health monitor](projects/01-server-health-monitor/) | Grades CPU, memory, load, disks and services OK/WARN/CRIT, logs history, alerts to Slack | `/proc`, awk, cron, webhooks, Nagios exit codes |
| [02 · Server bootstrap](projects/02-server-bootstrap/) | Turns a fresh Ubuntu or Rocky VM into a secure baseline in one command | users, SSH hardening, firewall, fail2ban, auto-updates |
| [03 · Deploy with rollback](projects/03-app-deploy-with-rollback/) | Zero-downtime releases with health checks and automatic rollback | symlinks, `flock`, curl, systemd, CI/CD |

## ⚡ Quick start

```bash
git clone https://github.com/vijaydevops678/linux-devops-essentials.git
cd linux-devops-essentials

./09-text-processing-logs/log-analyzer.sh 09-text-processing-logs/sample-access.log
./projects/01-server-health-monitor/health-check.sh
./12-security-hardening/ssh-hardening-check.sh -f 12-security-hardening/sample-sshd_config
./14-performance/perf-snapshot.sh
sudo ./15-linux-containers-internals/mini-container.sh -- ps aux
sudo ./19-troubleshooting-playbook/triage.sh
```

## 🧰 Script conventions

Every script in this repo follows the same rules, the ones you'd expect in production:

- `set -euo pipefail` strict mode: stop on the first error
- `-h` prints help; usage and examples are at the top of each file
- **Dry run first:** scripts that change the system support `-n` (or list-only by default)
- **Meaningful exit codes**, so they work in cron, CI/CD and monitoring (`0` OK, `1` problem found)
- No hard-coded secrets; settings come from options or environment variables
- Work on Ubuntu/Debian and RHEL/Rocky unless stated otherwise

## ⚠️ Safety

Scripts that change a system (users, packages, SSH, firewall, deploys) should be tried on a **throwaway VM** first: Multipass, VirtualBox or a free-tier cloud instance. Always run the dry run before the real run.

## 🗺️ Roadmap
- [ ] LVM and RAID in practice
- [ ] nftables / iptables deep dive
- [ ] SELinux and AppArmor basics
- [ ] SSH in depth: `~/.ssh/config`, jump hosts, agent forwarding
- [ ] Log shipping: rsyslog, logrotate and journald in production
- [ ] Project 4 · Load-balanced app: two app servers behind Nginx, with automated certificate renewal

## 👤 Author

**Vijay**: DevOps engineer · [GitHub](https://github.com/vijaydevops678)
