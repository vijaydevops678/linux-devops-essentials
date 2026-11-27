# 07 · Package Management

Installing, updating and pinning software is part of every server setup, Dockerfile and CI job. The commands differ per distribution, so you need to know both families.

## Debian / Ubuntu vs RHEL / Rocky / Amazon Linux

| Task | Debian / Ubuntu (`apt`) | RHEL / Rocky / Fedora (`dnf`) |
|---|---|---|
| Refresh package list | `sudo apt update` | `sudo dnf makecache` |
| Install | `sudo apt install -y nginx` | `sudo dnf install -y nginx` |
| Remove | `sudo apt remove nginx` | `sudo dnf remove nginx` |
| Upgrade everything | `sudo apt upgrade -y` | `sudo dnf upgrade -y` |
| Search | `apt search nginx` | `dnf search nginx` |
| Package info | `apt show nginx` | `dnf info nginx` |
| Is it installed? | `dpkg -s nginx` | `rpm -q nginx` |
| List installed | `apt list --installed` | `dnf list installed` |
| Which package owns a file? | `dpkg -S /usr/sbin/nginx` | `rpm -qf /usr/sbin/nginx` |
| Install a local file | `sudo apt install ./pkg.deb` | `sudo dnf install ./pkg.rpm` |
| Hold a version | `sudo apt-mark hold nginx` | `sudo dnf versionlock add nginx` |
| Remove unused dependencies | `sudo apt autoremove` | `sudo dnf autoremove` |
| Clean the cache | `sudo apt clean` | `sudo dnf clean all` |
| Repository config | `/etc/apt/sources.list.d/` | `/etc/yum.repos.d/` |

Others: Alpine `apk add` (common in Docker images), SUSE `zypper install`, Arch `pacman -S`.

**In Dockerfiles** combine update + install + cleanup in one layer:
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
```

## Script: `install-packages.sh`

Detects the package manager, refreshes the index, skips packages already installed and reports results. With no arguments it installs a DevOps toolkit (`curl wget git vim htop jq unzip tree tmux rsync`).

```bash
sudo ./install-packages.sh -n               # dry run: see what it would do
sudo ./install-packages.sh                  # install the default toolkit
sudo ./install-packages.sh -u nginx         # upgrade everything, then install nginx
```

## Practice tasks
1. Run the dry run on Ubuntu and on a Rocky Linux VM or container and compare the commands.
2. Find which package provides the `dig` command on each distribution.
3. Hold the version of one package, run an upgrade, and confirm it was not upgraded.
