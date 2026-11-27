# 18 · Environment and Shell Setup

"It works in my terminal but not in cron / sudo / the service" is almost always an **environment** problem: a different `PATH`, a missing variable, or a startup file that never ran. This topic explains where your shell gets its settings, and gives you a productive DevOps shell.

## Variables

| Task | Command |
|---|---|
| Set a shell variable (this shell only) | `NAME=value` |
| Export it to programs you start | `export NAME=value` |
| One command only | `NAME=value ./script.sh` |
| Show all exported variables | `env` · `printenv PATH` |
| Remove | `unset NAME` |
| Load a `.env` file | `set -a; source .env; set +a` |
| Environment of a running process | `sudo cat /proc/<PID>/environ \| tr '\0' '\n'` |

## Which startup file runs when?

| Shell type | Example | Files read |
|---|---|---|
| **Login** | SSH session, `su -`, `bash -l` | `/etc/profile` (+ `/etc/profile.d/*.sh`), then the **first** of `~/.bash_profile`, `~/.bash_login`, `~/.profile` |
| **Interactive non-login** | New terminal tab, typing `bash` | `/etc/bash.bashrc` (Ubuntu) or `/etc/bashrc` (RHEL), then `~/.bashrc` |
| **Non-interactive** | Scripts, cron jobs, `ssh host cmd` | Usually **none** of them |

Good practice: put everything in `~/.bashrc` and have `~/.bash_profile` load it with `[ -f ~/.bashrc ] && . ~/.bashrc`. For settings for **all users** add a file to `/etc/profile.d/`.

## PATH

`PATH` is the list of directories searched for commands, **left to right; first match wins**.

| Task | Command |
|---|---|
| Show it, one per line | `echo "$PATH" \| tr ':' '\n'` |
| Add a directory (in `~/.bashrc`) | `export PATH="$HOME/.local/bin:$PATH"` |
| What runs for a name? | `type -a python3` (shows aliases, functions and every file) |
| Clear the remembered location | `hash -r` (after installing a new version) |

## Where the environment differs

| Context | What happens | Fix |
|---|---|---|
| `sudo cmd` | `PATH` replaced by `secure_path`, most variables dropped | `sudo -E` to keep variables, or use full paths |
| cron | Minimal `PATH=/usr/bin:/bin`, no `.bashrc` | Set `PATH=` at the top of the crontab, use full paths |
| systemd service | Clean environment | `Environment=` or `EnvironmentFile=` in the unit |
| `ssh host 'cmd'` | Non-interactive: `.bashrc` often exits early | Use full paths or `bash -lc 'cmd'` |
| Docker container | Only `ENV` from the image + `-e` / `--env-file` | Pass variables explicitly |

## Productive shell: [`dotfiles/devops.bashrc`](dotfiles/devops.bashrc)

- **History:** 50,000 entries with timestamps, shared across terminals
- **Prompt:** `user@host:dir (git-branch) $`; the `$` turns red after a failed command, and a red **PROD** tag appears on hosts with `prod` in their name
- **Aliases:** `ll`, `gs`, `gl`, `d`, `dps`, `k`, `kgp`, `tf`, `sc`, `jf`, `ports`, `du1`, plus safer `cp`/`mv`/`rm`
- **Functions:** `mkcd`, `extract`, `port 8080`, `httpcode <url>`, `loadenv`, `b64d`, `myip`
- kubectl tab completion, also for the `k` alias

## Scripts

### `install-dotfiles.sh`: install or remove the shell setup safely
Copies `devops.bashrc` to `~/.config/devops-shell/` and adds one marked block to `~/.bashrc`. Backs up `~/.bashrc` first, never adds the block twice, and `-u` removes everything.

```bash
./install-dotfiles.sh -n      # dry run
./install-dotfiles.sh         # install, then: source ~/.bashrc
./install-dotfiles.sh -u      # uninstall
```

### `path-doctor.sh`: fix "command not found" and "wrong version"
Checks each `PATH` entry (missing, duplicate, empty, relative, world-writable), shows every copy of a command and which one wins, and lists your startup files and when each is read.

```bash
./path-doctor.sh
./path-doctor.sh -c python3,terraform,kubectl
```

## Practice tasks
1. Add `export GREETING=hello` to `~/.bashrc`, then check `echo $GREETING` in a new tab, in `bash -lc`, in `sudo`, and in a cron job.
2. Install two versions of a tool in different directories and use `path-doctor.sh -c` to see which one runs.
3. Install the dotfiles, rename a test VM's hostname to include `prod`, and see the warning in the prompt.
