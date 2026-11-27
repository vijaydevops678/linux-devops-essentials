# 14 · Performance Troubleshooting

"The site is slow" is vague. Your job is to find the **one resource that is the bottleneck**: CPU, memory, disk or network. Check them in order and the answer usually shows up within a minute.

## The USE method

For every resource check three things:

| | Question | Example |
|---|---|---|
| **U**tilisation | How busy is it? | CPU 95% busy, disk 100% busy |
| **S**aturation | Is work queueing? | Load > cores, swap activity, disk queue |
| **E**rrors | Is anything failing? | OOM kills, disk IO errors in `dmesg`, dropped packets |

## First-minute checklist

| # | Command | What to look for |
|---|---|---|
| 1 | `uptime` | Load average vs `nproc`. Rising or falling? |
| 2 | `dmesg -T \| tail` | OOM kills, disk errors, network drops |
| 3 | `vmstat 1 5` | `r` (run queue) > cores; `si`/`so` > 0 = swapping; `wa` = IO wait; `st` = steal |
| 4 | `mpstat -P ALL 1 3` | One core at 100% = a single-threaded bottleneck |
| 5 | `pidstat 1 3` | Which process uses the CPU |
| 6 | `iostat -xz 1 3` | `%util` near 100 and high `await` = slow or overloaded disk |
| 7 | `free -h` | `available` is what matters, not `free` |
| 8 | `sar -n DEV 1 3` | Network throughput vs the link's limit |
| 9 | `ss -s` | Connection counts, lots of `TIME-WAIT` or `CLOSE-WAIT` |
| 10 | `top` / `htop` | Confirm the picture |

`mpstat`, `pidstat`, `iostat` and `sar` come from the **sysstat** package: `sudo apt install sysstat` or `sudo dnf install sysstat`.

## Reading the numbers

| Metric | Meaning | Healthy |
|---|---|---|
| `us` / `sy` | Time in your code / in the kernel | High `sy` = many system calls or context switches |
| `wa` (iowait) | CPU idle, waiting for disk | Below ~10% |
| `st` (steal) | Hypervisor gave your CPU to another VM | Near 0. High on burstable cloud instances (T-series) when credits run out |
| Load average | Processes running + waiting (incl. disk wait) | Below the number of cores |
| `available` memory | What can be used without swapping | Above ~10% of RAM |
| `%util` (disk) | Time the disk was busy | Below ~80% |
| `await` (disk) | Average ms per IO request | SSD < 5 ms; network disks more |

## Deeper tools

| Tool | Use |
|---|---|
| `strace -cp <PID>` | Which system calls a process spends time in |
| `perf top` | Which functions use the CPU (kernel and user space) |
| `iotop` | Which process does the IO |
| `lsof -p <PID>` | Files and sockets a process holds |
| `/proc/<PID>/status` | Memory (`VmRSS`), threads, context switches |
| `journalctl -k \| grep -i oom` | Processes killed by the OOM killer |

## Script: `perf-snapshot.sh`

Samples the kernel counters in `/proc` and prints CPU split (user / system / iowait / steal), run queue, memory and swap activity, disk throughput and busy %, network throughput, top processes, processes stuck on IO and recent OOM kills, then a **plain-language verdict** naming the bottleneck. Needs only `/proc`, so it works on minimal servers and inside containers.

```bash
./perf-snapshot.sh            # 5-second sample
./perf-snapshot.sh -i 10      # 10-second sample
```

## Practice tasks
1. Run `yes > /dev/null &` once per core, run the script, and confirm the verdict blames the CPU. Then `pkill yes`.
2. Generate disk load with `dd if=/dev/zero of=/tmp/test bs=1M count=2000 oflag=direct` and watch iowait and disk busy % rise.
3. Install sysstat and compare `vmstat 1` and `iostat -xz 1` with what the script reports.
