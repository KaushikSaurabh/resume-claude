#!/usr/bin/env bash
# UserPromptSubmit hook (macOS/Linux twin of limit-guard.ps1): manages rate-limit
# hold + self-resume signalling. On exit 0, stdout is injected into the session as
# context (instructions to the model).
#
# The hook CANNOT call ScheduleWakeup (model-only tool). It detects state and TELLS the
# session what to do. Refresh detection is CLOCK-BASED (now vs last known reset epoch),
# so it works even when the window is idle and ratelimit.json is stale.
#
# Files (all under ~/.claude/): ratelimit.json (read), .limit-hold (r/w, reset epoch),
# .limit-config (read, int %/off), .limit-override (read, presence), .wake-intent (write).
# Env override: CLAUDE_LIMIT_OVERRIDE=1
#
# Needs `jq` for JSON parsing (standard on most dev Macs via brew; the hook exits 0
# silently if jq or the data file is missing, so a missing dep never blocks a prompt).

cat >/dev/null 2>&1 || true   # drain stdin (the hook payload); we don't need it
CLAUDE_DIR="$HOME/.claude"

# Override -> silent
[ "$CLAUDE_LIMIT_OVERRIDE" = "1" ] && exit 0
[ -f "$CLAUDE_DIR/.limit-override" ] && exit 0

# Configurable hold threshold (default 90). ~/.claude/.limit-config: single int line, or "off".
hold_pct=90
cfg_file="$CLAUDE_DIR/.limit-config"
if [ -f "$cfg_file" ]; then
  cfg="$(head -n1 "$cfg_file" | tr -d '[:space:]')"
  [ "$cfg" = "off" ] && exit 0
  case "$cfg" in ''|*[!0-9]*) : ;; *) if [ "$cfg" -ge 1 ] && [ "$cfg" -le 100 ]; then hold_pct="$cfg"; fi ;; esac
fi
soft_pct=$(( hold_pct - 10 )); [ "$soft_pct" -lt 0 ] && soft_pct=0

rl_file="$CLAUDE_DIR/ratelimit.json"
hold_file="$CLAUDE_DIR/.limit-hold"
now=$(date +%s)

# ---------- CASE A: in a HOLD ----------
if [ -f "$hold_file" ]; then
  hold_epoch="$(head -n1 "$hold_file" | tr -d '[:space:]')"
  case "$hold_epoch" in ''|*[!0-9]*) hold_epoch=0 ;; esac
  if [ "$now" -ge "$hold_epoch" ]; then
    rm -f "$hold_file" "$CLAUDE_DIR/.wake-intent"
    echo "[LIMIT GUARD] Quota window has RESET (clock-confirmed). The hold is cleared - you may RESUME the held work now. Pick up from STATE.md / the resume note you wrote before holding."
  else
    wait_min=$(( (hold_epoch - now) / 60 ))
    redelay=$(( hold_epoch - now + 30 )); [ "$redelay" -gt 3600 ] && redelay=3600   # cap at ScheduleWakeup max; chains until reset
    echo "[LIMIT GUARD] Still holding for quota refresh (~${wait_min}m left). Do NOT resume heavy work. CALL THE ScheduleWakeup TOOL now with delaySeconds=${redelay} and prompt='Quota refreshed - resume the held work from STATE.md', then STOP. This re-arms the same-window auto-resume so no keystroke is needed at reset."
  fi
  exit 0
fi

# ---------- CASE B: normal operation ----------
# CASE B parses ratelimit.json -> needs jq. If absent, fail open (silent) rather than block
# prompts. (CASE A above needs no jq, so a held session still releases without it.)
command -v jq >/dev/null 2>&1 || exit 0
[ -f "$rl_file" ] || exit 0
p5="$(jq -r '."anthropic-ratelimit-unified-5h-utilization" // 0' "$rl_file" 2>/dev/null)" || exit 0
pw="$(jq -r '."anthropic-ratelimit-unified-7d-utilization" // 0' "$rl_file" 2>/dev/null)" || exit 0

# Compare/round as integer percents (avoid bc dependency): pct = round(frac*100).
to_pct() { awk -v v="$1" 'BEGIN{printf "%d", (v*100)+0.5}'; }
p5i=$(to_pct "$p5"); pwi=$(to_pct "$pw")
if [ "$p5i" -ge "$pwi" ]; then pct=$p5i; which="5-hour"; reset_key="anthropic-ratelimit-unified-5h-reset";
else pct=$pwi; which="weekly"; reset_key="anthropic-ratelimit-unified-7d-reset"; fi

reset_epoch="$(jq -r --arg k "$reset_key" '.[$k] // 0' "$rl_file" 2>/dev/null)"
case "$reset_epoch" in ''|*[!0-9]*) reset_epoch=0 ;; esac

# STALENESS GUARD: recorded reset already in the past -> fossil data, stay silent.
if [ "$reset_epoch" -gt 0 ] && [ "$now" -ge "$reset_epoch" ]; then exit 0; fi

if [ "$reset_epoch" -gt "$now" ]; then mins=$(( (reset_epoch - now) / 60 )); else mins=0; fi
if [ "$mins" -gt 0 ]; then reset_txt="resets in ~$(( mins/60 ))h$(( mins%60 ))m"; else reset_txt="reset imminent"; fi

if [ "$pct" -ge "$hold_pct" ]; then
  [ "$reset_epoch" -gt "$now" ] && printf '%s\n' "$reset_epoch" > "$hold_file"
  headroom=$(( 100 - pct ))
  secs=$(( reset_epoch - now ))
  # >5h out (effectively the weekly window, days away): chaining is silly -> manual return.
  # ponytail: 5h cutoff, tune if a mid-length limit tier ever appears.
  if [ "$secs" -gt 18000 ]; then
    days=$(( secs / 86400 )); hrs=$(( (secs % 86400) / 3600 ))
    echo "[LIMIT GUARD] $which limit at ${pct}% - resets in ~${days}d${hrs}h, too far for same-window auto-resume (ScheduleWakeup maxes at 1h and this is days out). PERSIST STATE.md now and STOP. Come back after it resets (~${days}d${hrs}h) and continue manually - do NOT schedule a wake. Override: CLAUDE_LIMIT_OVERRIDE=1."
  else
    if [ "$reset_epoch" -gt "$now" ]; then raw=$(( secs + 30 )); else raw=300; fi
    delay=$raw; [ "$delay" -gt 3600 ] && delay=3600   # cap at ScheduleWakeup max; CASE A re-arms further hops
    more=""; [ $(( secs + 30 )) -gt 3600 ] && more=" (reset is >1h out; this wake lands early and re-arms automatically until quota refreshes)"
    printf '{\n "fire_epoch": %s,\n "armed_at": %s\n}\n' "$(( now + delay ))" "$now" > "$CLAUDE_DIR/.wake-intent"
    echo "[LIMIT GUARD] $which limit at ${pct}% (${reset_txt}), ~${headroom}% headroom. DO THIS NOW, in this turn, in order: (1) persist working state to STATE.md (done / next / open threads); (2) CALL THE ScheduleWakeup TOOL with delaySeconds=${delay} and prompt='Quota refreshed - resume the held work from STATE.md'; (3) then STOP without further work.${more} Step 2 is the auto-resume - this same window will re-invoke itself, no keystroke needed. If a task is one or two steps from done and fits ~${headroom}%, finish it first and say so. Override: CLAUDE_LIMIT_OVERRIDE=1."
  fi
elif [ "$pct" -ge "$soft_pct" ]; then
  echo "[LIMIT GUARD] Heads-up: $which usage at ${pct}% (${reset_txt}). Prefer smaller, checkpointable steps; hard hold fires at ${hold_pct}%."
fi
exit 0
