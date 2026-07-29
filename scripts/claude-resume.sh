#!/usr/bin/env bash
# Arm / disarm / check the one-shot auto-resume marker (macOS/Linux twin of claude-resume.ps1).
#   claude-resume.sh arm [prompt]   # arm: relaunch in $PWD when limits refresh
#   claude-resume.sh off            # disarm
#   claude-resume.sh status         # show state
# Marker (~/.claude/.resume-armed) is consumed once by the launchd job on refresh.

marker="$HOME/.claude/.resume-armed"
action="${1:-status}"
default_prompt="Resume the work described in STATE.md in this directory. Read it first, then continue from where it left off."

case "$action" in
  arm)
    cwd="$PWD"
    prompt="${2:-$default_prompt}"
    armed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if command -v jq >/dev/null 2>&1; then
      jq -n --arg cwd "$cwd" --arg prompt "$prompt" --arg armed_at "$armed_at" \
        '{cwd:$cwd, prompt:$prompt, armed_at:$armed_at}' > "$marker"
    else
      # jq absent: escape backslashes and double-quotes for valid JSON.
      esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
      printf '{"cwd":"%s","prompt":"%s","armed_at":"%s"}\n' "$(esc "$cwd")" "$(esc "$prompt")" "$armed_at" > "$marker"
    fi
    echo "Auto-resume ARMED. On next limit refresh, will continue: claude --continue in $cwd"
    ;;
  off)
    if [ -f "$marker" ]; then rm -f "$marker"; echo "Auto-resume disarmed."; else echo "Auto-resume was not armed."; fi
    ;;
  status)
    if [ -f "$marker" ]; then echo "Auto-resume: ARMED"; cat "$marker"; echo; else echo "Auto-resume: off"; fi
    ;;
  *) echo "usage: claude-resume.sh [arm [prompt]|off|status]" >&2; exit 1 ;;
esac
