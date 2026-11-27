# devops.bashrc - history, aliases, functions and a useful prompt for DevOps work.
# Installed by install-dotfiles.sh and loaded from ~/.bashrc. Edit freely.

# ---------- history: big, timestamped, shared between terminals ----------
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T  '
shopt -s histappend

# ---------- safer file operations ----------
alias cp='cp -i'
alias mv='mv -i'
alias rm='rm -I'

# ---------- everyday shortcuts ----------
alias ll='ls -lah --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias df='df -h'
alias free='free -h'
alias du1='du -h --max-depth=1 2>/dev/null | sort -rh | head -20'
alias ports='sudo ss -tulpn'
alias psg='ps aux | grep -v grep | grep -i'
alias reload='source ~/.bashrc'

# ---------- tools ----------
alias g='git'
alias gs='git status -sb'
alias gl='git log --oneline --graph --decorate -20'
alias d='docker'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias k='kubectl'
alias kgp='kubectl get pods -o wide'
alias tf='terraform'
alias sc='sudo systemctl'
alias jf='sudo journalctl -f -u'

# kubectl tab completion, also for the "k" alias
if command -v kubectl >/dev/null 2>&1; then
  # shellcheck disable=SC1090
  source <(kubectl completion bash)
  complete -o default -F __start_kubectl k
fi

# ---------- functions ----------
# Make a directory and go into it
mkcd() { mkdir -p "$1" && cd "$1" || return; }

# Extract any common archive
extract() {
  case "$1" in
    *.tar.gz|*.tgz) tar -xzf "$1" ;;
    *.tar.bz2)      tar -xjf "$1" ;;
    *.tar.xz)       tar -xJf "$1" ;;
    *.tar)          tar -xf "$1" ;;
    *.zip)          unzip "$1" ;;
    *.gz)           gunzip "$1" ;;
    *)              echo "Don't know how to extract '$1'" ;;
  esac
}

# Who is listening on a port?   port 8080
port() { sudo ss -ltnp "sport = :$1"; }

# HTTP status and response time   httpcode https://example.com
httpcode() { curl -s -o /dev/null -w '%{http_code}  %{time_total}s\n' "$1"; }

# Load a .env file into this shell   loadenv  (or loadenv path/to/file)
loadenv() { set -a; source "${1:-.env}"; set +a; echo "Loaded ${1:-.env}"; }

# Decode base64, e.g. a Kubernetes secret value
b64d() { echo "$1" | base64 -d; echo; }

# Your public IP address
myip() { curl -s https://ifconfig.me; echo; }

# ---------- prompt: user@host:dir (git branch), red $ after a failed command, PROD warning ----------
__devops_prompt() {
  local status=$? branch tag="" symbol
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$(hostname)" == *prod* ]]; then
    tag='\[\e[41;97m\] PROD \[\e[0m\] '
  fi
  if (( status == 0 )); then symbol='\[\e[32m\]\$\[\e[0m\]'; else symbol='\[\e[31m\]\$\[\e[0m\]'; fi
  PS1="${tag}\[\e[36m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]${branch:+ \[\e[33m\]($branch)\[\e[0m\]} ${symbol} "
  history -a
}
if [[ "${PROMPT_COMMAND:-}" != *__devops_prompt* ]]; then
  PROMPT_COMMAND="__devops_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
