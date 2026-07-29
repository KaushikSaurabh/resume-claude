#!/usr/bin/env bash
# Claude Code rate-limit proxy auto-start (macOS/Linux twin of proxy-autostart.ps1).
# Source this from your shell rc (~/.zshrc or ~/.bashrc). Starts the fail-open proxy if
# nothing is listening on the port, then points Claude Code at it.
# OFF-SWITCH: export CLAUDE_PROXY_OFF=1 before launching a shell, or remove the source line.

[ "$CLAUDE_PROXY_OFF" = "1" ] && return 0 2>/dev/null || true

_rc_proxy_script="$HOME/.claude/ratelimit-proxy.mjs"
_rc_port="${CLAUDE_PROXY_PORT:-8787}"

_rc_listening() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$_rc_port" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$_rc_port" >/dev/null 2>&1
  else
    return 1   # can't tell -> assume not listening, we'll try to start
  fi
}

if ! _rc_listening && [ -f "$_rc_proxy_script" ] && command -v node >/dev/null 2>&1; then
  # Detached, no terminal noise. nohup keeps it alive after the shell exits.
  nohup node "$_rc_proxy_script" >/dev/null 2>&1 &
  disown 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    _rc_listening && break
    sleep 0.2
  done
fi

# FAIL-SAFE: only route through the proxy if it is actually listening; otherwise leave
# ANTHROPIC_BASE_URL UNSET so Claude reaches the API directly (no capture, never bricked).
if _rc_listening; then
  export ANTHROPIC_BASE_URL="http://127.0.0.1:$_rc_port"
else
  unset ANTHROPIC_BASE_URL
  echo "[proxy-autostart] rate-limit proxy not listening on $_rc_port - running WITHOUT it (direct API). Rate-limit fields will show n/a." >&2
fi

unset -f _rc_listening 2>/dev/null || true
unset _rc_proxy_script _rc_port 2>/dev/null || true
