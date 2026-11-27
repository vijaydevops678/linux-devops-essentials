# 01 · Shell Scripting Basics

Every DevOps task you automate on Linux (deployments, backups, health checks, server setup) starts as a bash script. Writing them safely is the first skill to master.

## Core concepts

| Concept | Syntax | Notes |
|---|---|---|
| Shebang | `#!/usr/bin/env bash` | First line; picks the interpreter |
| Strict mode | `set -euo pipefail` | Stop on errors, unset variables and pipe failures |
| Variable | `name="value"` → `"$name"` | No spaces around `=`; always quote when using |
| Command output | `today=$(date +%F)` | Prefer `$(...)` over backticks |
| Arithmetic | `$(( a + b ))`, `(( a > b ))` | Integers only |
| Test file / string | `[[ -f file ]]`, `[[ -z "$x" ]]` | `-f` file, `-d` dir, `-z` empty, `-n` not empty |
| Loop | `for x in a b c; do ...; done` | Also `while read -r line; do ...; done < file` |
| Function | `name() { local x=$1; ... }` | Use `local` for variables inside functions |
| Exit code | `$?`, `exit 1` | `0` = success, anything else = failure |
| Options | `while getopts ":nvh" opt` | Standard way to parse `-n -v -h` flags |
| Cleanup | `trap cleanup EXIT` | Runs on exit, even after an error |
| Default value | `${VAR:-default}` | Use when a variable may be empty |

## Scripts

### `script-template.sh`: copy this for every new script
Strict mode, timestamped logging, `-n` dry run, `-v` verbose, `-h` help, dependency checks and automatic cleanup.

```bash
./script-template.sh -h
./script-template.sh -v world        # verbose
./script-template.sh -n world        # dry run: prints commands instead of running them
```

### `bash-basics-demo.sh`: every concept with live output
```bash
./bash-basics-demo.sh
```

## Practice tasks
1. Copy `script-template.sh` and turn it into a script that prints the size of a directory passed as an argument.
2. Add a `-o <file>` option that writes the output to a file.
3. Make the script exit with code `2` if the directory does not exist, and check it with `echo $?`.
