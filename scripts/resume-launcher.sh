#!/usr/bin/env bash
# Auto re-launcher (macOS/Linux twin of resume-launcher.ps1). When rate limits refresh AND
# a resume is ARMED, opens ONE fresh `claude --continue` in the saved dir. Run every ~5 min
# by a launchd job (macOS) or cron (Linux). One-shot: marker deleted before launch.
#
# ponytail: "refreshed" = binding window utilization < 0.5. Coarse, but re-checked every
#           5 min and the marker is one-shot, so a missed edge self-heals.

CLAUDE_DIR="$HOME/.claude"
marker="$CLAUDE_DIR/.resume-armed"
rl_file="$CLAUDE_DIR/ratelimit.json"
log="$CLAUDE_DIR/resume-launcher.log"
intent="$CLAUDE_DIR/.wake-intent"
now=$(date +%s)
stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

command -v jq >/dev/null 2>&1 || exit 0

# FALLBACK GATE: the PRIMARY resume is the in-session ScheduleWakeup, which deletes
# .wake-intent when the hold releases. This launcher is only a safety net for a CLOSED
# window. Require .wake-intent to still exist AND be >5min overdue before acting.
if [ -f "$intent" ]; then
  fire="$(jq -r '.fire_epoch // 0' "$intent" 2>/dev/null)"
  case "$fire" in ''|*[!0-9]*) fire=0 ;; esac
  if [ "$now" -lt $(( fire + 300 )) ]; then exit 0; fi   # not overdue -> let in-session wake handle it
  rm -f "$intent"
  echo "$stamp FALLBACK wake-intent overdue, launcher taking over" >> "$log"
fi

[ -f "$marker" ] || exit 0
[ -f "$rl_file" ] || exit 0

p5="$(jq -r '."anthropic-ratelimit-unified-5h-utilization" // 0' "$rl_file" 2>/dev/null)"
pw="$(jq -r '."anthropic-ratelimit-unified-7d-utilization" // 0' "$rl_file" 2>/dev/null)"
# refreshed when the binding window is back under 50% (integer *1000 compare, no bc).
maxk="$(awk -v a="$p5" -v b="$pw" 'BEGIN{m=(a>b)?a:b; printf "%d", m*1000}')"
[ "$maxk" -ge 500 ] && exit 0

cwd="$(jq -r '.cwd // empty' "$marker" 2>/dev/null)"; [ -z "$cwd" ] && cwd="$HOME"
prompt="$(jq -r '.prompt // empty' "$marker" 2>/dev/null)"
[ -z "$prompt" ] && prompt="Resume the work described in STATE.md in this directory. Read it first, then continue from where it left off."

# Fire once. Delete marker FIRST so we can never double-launch.
rm -f "$marker"
echo "$stamp LAUNCH cwd=$cwd util=$(( maxk/10 ))% prompt=$(printf '%.80s' "$prompt")" >> "$log"

# Resume the ACTUAL prior session (full transcript/context) via `claude --continue`.
# On macOS, open a NEW visible Terminal window via osascript so the user can see/interact.
# Escape embedded double-quotes for the AppleScript string.
esc_cwd="$(printf '%s' "$cwd" | sed 's/"/\\"/g')"
esc_prompt="$(printf '%s' "$prompt" | sed 's/"/\\"/g')"
if command -v osascript >/dev/null 2>&1; then
  osascript -e "tell application \"Terminal\" to do script \"cd \\\"$esc_cwd\\\" && claude --continue \\\"$esc_prompt\\\"\"" >/dev/null 2>&1 \
    && echo "$stamp OK resumed via --continue in new Terminal window" >> "$log" \
    || echo "$stamp ERROR osascript launch failed" >> "$log"
else
  # Linux / headless fallback: run detached in the background.
  ( cd "$cwd" && nohup claude --continue "$prompt" >/dev/null 2>&1 & ) \
    && echo "$stamp OK resumed via --continue (background, no terminal)" >> "$log" \
    || echo "$stamp ERROR background launch failed" >> "$log"
fi
exit 0
