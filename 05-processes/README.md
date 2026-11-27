# 05 · Processes

When a server is slow or an app is stuck, you need to find the process, understand what it is doing, and stop or restart it safely.

## Key ideas

- Every program runs as a **process** with a **PID** and a parent (**PPID**).
- **Load average** = processes running or waiting for CPU. Compare it with the number of cores (`nproc`): a load of 8 on 4 cores means work is queueing.
- **Process states:** `R` running · `S` sleeping · `D` waiting on disk/IO (can't be killed) · `Z` zombie (finished, parent hasn't collected it) · `T` stopped.
- **Signals:** `SIGTERM (15)` asks politely, `SIGKILL (9)` forces, `SIGHUP (1)` often means "reload config".

## Essential commands

| Task | Command |
|---|---|
| All processes | `ps aux` · `ps -ef` |
| Process tree | `ps -ef --forest` · `pstree -p` |
| Live view | `top` (press `P` CPU, `M` memory, `k` kill) · `htop` |
| Top CPU users | `ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu \| head` |
| Find a PID by name | `pgrep -a nginx` |
| Stop gracefully / force | `kill <PID>` · `kill -9 <PID>` |
| Stop by name | `pkill -f "python app.py"` |
| Reload config | `kill -HUP <PID>` |
| Run in background, survive logout | `nohup ./job.sh > job.log 2>&1 &` |
| Jobs in this shell | `jobs` · `fg %1` · `bg %1` |
| Change priority | `nice -n 10 ./backup.sh` · `renice 5 -p <PID>` |
| Open files / ports of a process | `lsof -p <PID>` · `lsof -i :8080` |
| What a process is doing | `strace -p <PID>` |
| Memory overview | `free -h` · `vmstat 1 5` |

## Script: `process-monitor.sh`

Load vs cores, top processes by CPU and memory, processes per user and zombies. Use `-w` to check a process is running and `-c` to alert on CPU hogs; both make the script exit with code `1`, so it works in cron or monitoring.

```bash
./process-monitor.sh
./process-monitor.sh -n 10
./process-monitor.sh -w nginx -c 90
```

## Practice tasks
1. Start `sleep 600 &`, find it with `pgrep`, then stop it with `kill`.
2. Run `yes > /dev/null &` to burn CPU, find it with the script's `-c 50` option, then kill it.
3. Start a job with `nohup`, log out and back in, and confirm it is still running.
