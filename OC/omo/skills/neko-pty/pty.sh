#!/usr/bin/env bash
# OML PTY control helper — battle-tested tmux wrapper for driving interactive TUIs.
# Born from real OC1/OC2 verification sessions; encodes the gotchas so agents don't re-learn them.
# Zero runtime deps beyond tmux. All sessions are prefixed oml- and never touch production servers.
set -euo pipefail

PREFIX="oml-"
LEADER_SLEEP="0.7"   # leader key (C-x) needs a pause before the combo key, else the combo drops
RENDER_SLEEP="1.5"   # default wait after launching / opening a view

die() { printf 'pty.sh: %s\n' "$*" >&2; exit 2; }
need() { [ "$#" -ge 1 ] || die "missing argument ($1)"; }

cmd_start() {
  need "${1:-session}"
  local s="$1" dir="${2:-/home/miao}" prog="${3:-opencode}"
  [[ "$s" == "$PREFIX"* ]] || die "session must start with '$PREFIX' (got: $s)"
  command -v tmux >/dev/null || die "tmux not installed"
  if tmux has-session -t "$s" 2>/dev/null; then die "session '$s' already exists (use stop first)"; fi
  tmux new-session -d -s "$s" -x 220 -y 56 -c "$dir"
  # TERM is empty in this env; must be set inline for the TUI to render colors/lines.
  tmux send-keys -t "$s" "TERM=xterm-256color $prog" Enter
  printf 'started %s in %s: %s\n' "$s" "$dir" "$prog"
}

cmd_send() {
  need "${1:-session}"; local s="$1"; shift
  [ "$#" -ge 1 ] || die "send needs at least one key"
  tmux send-keys -t "$s" "$@"
}

cmd_lit() {
  need "${1:-session}"; need "${2:-text}"
  local s="$1"; shift
  tmux send-keys -t "$s" -l "$*"
}

# leader combo: send C-x, pause, then the combo key. Single send of both drops one.
cmd_leader() {
  need "${1:-session}"; need "${2:-key}"
  local s="$1" key="$2"
  tmux send-keys -t "$s" C-x
  sleep "$LEADER_SLEEP"
  tmux send-keys -t "$s" "$key"
}

# clear the input line first (Escape), then type a slash command, then Enter.
cmd_cmd() {
  need "${1:-session}"; need "${2:-command}"
  local s="$1" text="$2"
  tmux send-keys -t "$s" Escape
  sleep 0.2
  tmux send-keys -t "$s" -l "$text"
  tmux send-keys -t "$s" Enter
}

# open /sessions, go down n rows, Enter to load that session.
cmd_nav() {
  need "${1:-session}"; need "${2:-rows}"
  local s="$1" n="$2" i
  cmd_cmd "$s" "/sessions"
  sleep "$RENDER_SLEEP"
  for ((i=0; i<n; i++)); do
    tmux send-keys -t "$s" Down
    sleep 0.15
  done
  tmux send-keys -t "$s" Enter
  sleep "$RENDER_SLEEP"
}

cmd_capture() {
  need "${1:-session}"; local s="$1" lines="${2:-}"
  if [ -n "$lines" ]; then tmux capture-pane -t "$s" -p -S "-$lines"
  else tmux capture-pane -t "$s" -p; fi
}

cmd_wait() {
  need "${1:-session}"; need "${2:-pattern}"
  local s="$1" pat="$2" secs="${3:-12}" i
  for ((i=0; i<secs; i++)); do
    if cmd_capture "$s" | grep -Fq -- "$pat"; then
      printf 'matched %q after %ss\n' "$pat" "$i"; return 0
    fi
    sleep 1
  done
  printf 'timeout: pattern %q not seen in %ss\n' "$pat" "$secs" >&2
  return 1
}

cmd_stop() {
  need "${1:-session}"; local s="$1"
  [[ "$s" == "$PREFIX"* ]] || die "refusing to stop non-oml session '$s'"
  tmux kill-session -t "$s" 2>/dev/null || true
  printf 'stopped %s\n' "$s"
}

cmd_list() { tmux list-sessions 2>/dev/null | grep "^$PREFIX" || true; }

usage() {
  cat <<'EOF'
Usage: pty.sh <command> [args...]
  start   <session> <dir> [prog]      start detached session (default: TERM=xterm-256color opencode)
  send    <session> <key>...          send tmux key names (e.g. Enter Down C-c)
  lit     <session> <text>            send literal text
  leader  <session> <key>             leader combo: C-x, pause, key (single send drops combo)
  cmd     <session> <slash-cmd>       clear input (Escape), type slash command, Enter
  nav     <session> <rows>            open /sessions, down N, Enter to load session
  capture <session> [lines]           capture pane (optionally last N lines)
  wait    <session> <pattern> [secs]  poll capture until pattern appears
  stop    <session>                   kill only an oml- session
  list                                list oml- sessions

All session names must start with 'oml-'. Never kills production servers.
EOF
}

main() {
  [ "$#" -ge 1 ] || { usage; exit 1; }
  local c="$1"; shift
  case "$c" in
    start)   cmd_start "$@" ;;
    send)    cmd_send "$@" ;;
    lit)     cmd_lit "$@" ;;
    leader)  cmd_leader "$@" ;;
    cmd)     cmd_cmd "$@" ;;
    nav)     cmd_nav "$@" ;;
    capture) cmd_capture "$@" ;;
    wait)    cmd_wait "$@" ;;
    stop)    cmd_stop "$@" ;;
    list)    cmd_list "$@" ;;
    -h|--help|help) usage ;;
    *) die "unknown command '$c' (try --help)" ;;
  esac
}

main "$@"
