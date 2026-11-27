# 17 · Kernel Tuning and Limits

Default kernel settings suit a laptop, not a server handling thousands of connections. "Too many open files", dropped connections under load, and a Kubernetes node that won't join a cluster usually come down to the settings in this topic.

## sysctl: kernel settings at runtime

Every setting is a file under `/proc/sys`: `net.core.somaxconn` is `/proc/sys/net/core/somaxconn`.

| Task | Command |
|---|---|
| Read a value | `sysctl net.core.somaxconn` |
| Change it until reboot | `sudo sysctl -w net.core.somaxconn=4096` |
| Make it permanent | Put it in `/etc/sysctl.d/99-devops.conf`, then `sudo sysctl --system` |
| Show everything | `sysctl -a` |

Settings worth knowing (see [`99-devops.conf`](99-devops.conf) for a ready-to-use file):

| Setting | Why you'd change it |
|---|---|
| `fs.file-max` | System-wide limit on open files |
| `fs.inotify.max_user_watches` | "ENOSPC: System limit for number of file watchers reached" |
| `net.core.somaxconn` | Busy web servers dropping new connections |
| `net.ipv4.ip_local_port_range` | Proxies running out of source ports for outgoing connections |
| `net.ipv4.tcp_tw_reuse` | Lots of `TIME-WAIT` sockets on servers making many outgoing connections |
| `vm.swappiness` | Lower it on database servers to avoid swapping |
| `vm.max_map_count` | Elasticsearch / OpenSearch refuse to start below 262144 |
| `net.ipv4.ip_forward` | Must be `1` for Docker networking and Kubernetes |

## ulimit: per-process limits

The most famous one is **open files** (`nofile`); every socket counts as a file.

| Task | Command |
|---|---|
| Your shell's limits | `ulimit -a` · open files: `ulimit -n` (soft) / `ulimit -Hn` (hard) |
| A running process's limits | `cat /proc/<PID>/limits` |
| How many files it has open | `ls /proc/<PID>/fd \| wc -l` · `lsof -p <PID>` |
| For login sessions | `/etc/security/limits.d/90-nofile.conf`: `* soft nofile 65535` and `* hard nofile 65535` |
| **For systemd services** | `sudo systemctl edit myapp` → add `[Service]` and `LimitNOFILE=65535`, then restart |

**Common trap:** `/etc/security/limits.conf` only applies to login sessions (PAM). Services started by systemd ignore it; set `LimitNOFILE=` in the unit instead.

## Kernel modules

| Task | Command |
|---|---|
| Loaded modules | `lsmod` |
| Info about a module | `modinfo br_netfilter` |
| Load now | `sudo modprobe br_netfilter` |
| Load at every boot | `echo br_netfilter \| sudo tee /etc/modules-load.d/k8s.conf` |
| Kernel messages | `dmesg -T \| tail` |

Kubernetes nodes need `overlay` and `br_netfilter` loaded, the bridge sysctls set to `1`, IP forwarding on, and (by default) swap off.

## Script: `kernel-limits-audit.sh`

Checks the important sysctl values against recommendations, system-wide file handle usage, the five processes closest to their open-file limit, and with `-k` the Kubernetes node prerequisites. Exits with code `1` if there are warnings.

```bash
sudo ./kernel-limits-audit.sh
sudo ./kernel-limits-audit.sh -k      # also check Kubernetes prerequisites
```

## Practice tasks
1. Run `ulimit -n 50` in a shell, then `python3 -c "import socket; [socket.socket() for _ in range(100)]"` to reproduce "Too many open files".
2. Raise `LimitNOFILE` for a systemd service and confirm the change in `/proc/<PID>/limits`.
3. Prepare a VM for Kubernetes until `kernel-limits-audit.sh -k` reports no warnings.
