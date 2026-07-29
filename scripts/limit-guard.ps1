# UserPromptSubmit hook: manages rate-limit hold + self-resume signalling.
# On exit 0, stdout is injected into the session as context (instructions to the model).
#
# The hook CANNOT call ScheduleWakeup (that is a model-only tool). It detects state and
# TELLS the session what to do. Refresh detection is CLOCK-BASED (compare now vs the last
# known reset epoch), so it works even when the window is idle and ratelimit.json is stale.
#
# Files:
#   ~/.claude/ratelimit.json  (read)  proxy-captured headers: -{5h,7d}-utilization, -{5h,7d}-reset
#   ~/.claude/.limit-hold     (r/w)   single line = reset epoch we are holding until (set when we go >=90%)
#   ~/.claude/.limit-override (read)  presence = silence the guard
# Override env: CLAUDE_LIMIT_OVERRIDE=1

$ErrorActionPreference = 'SilentlyContinue'
[Console]::In.ReadToEnd() | Out-Null

if ($env:CLAUDE_LIMIT_OVERRIDE -eq '1' -or (Test-Path (Join-Path $HOME '.claude/.limit-override'))) { exit 0 }

# Configurable hold threshold (percent). Default 90. Set via ~/.claude/.limit-config (single int line).
# The file content "off" disables the guard entirely.
$holdPct = 90
$cfgFile = Join-Path $HOME '.claude/.limit-config'
if (Test-Path $cfgFile) {
    $cfg = (Get-Content $cfgFile -First 1).Trim()
    if ($cfg -eq 'off') { exit 0 }
    $n = 0; if ([int]::TryParse($cfg, [ref]$n) -and $n -ge 1 -and $n -le 100) { $holdPct = $n }
}
$softPct = [math]::Max(0, $holdPct - 10)   # soft heads-up 10 points below the hold

$rlFile   = Join-Path $HOME '.claude/ratelimit.json'
$holdFile = Join-Path $HOME '.claude/.limit-hold'
$now = [datetimeoffset]::UtcNow.ToUnixTimeSeconds()

# ---------- CASE A: we are in a HOLD (previously hit >=90% and armed a wait) ----------
if (Test-Path $holdFile) {
    $holdEpoch = 0
    try { $holdEpoch = [long]((Get-Content $holdFile -First 1).Trim()) } catch {}
    if ($now -ge $holdEpoch) {
        # CLOCK says the window we were holding for has reset. Release the hold.
        Remove-Item $holdFile -Force
        Remove-Item (Join-Path $HOME '.claude/.wake-intent') -Force -ErrorAction SilentlyContinue  # resume happening now; cancel fallback
        Write-Output "[LIMIT GUARD] Quota window has RESET (clock-confirmed). The hold is cleared - you may RESUME the held work now. Pick up from STATE.md / the resume note you wrote before holding."
    } else {
        $wait = [int](($holdEpoch - $now) / 60)
        $redelay = [math]::Min(($holdEpoch - $now) + 30, 3600)   # cap at ScheduleWakeup max; chains until reset
        Write-Output "[LIMIT GUARD] Still holding for quota refresh (~${wait}m left). Do NOT resume heavy work. CALL THE ScheduleWakeup TOOL now with delaySeconds=$redelay and prompt='Quota refreshed - resume the held work from STATE.md', then STOP. This re-arms the same-window auto-resume so no keystroke is needed at reset."
    }
    exit 0
}

# ---------- CASE B: normal operation, read live usage ----------
if (-not (Test-Path $rlFile)) { exit 0 }
try { $rl = Get-Content $rlFile -Raw | ConvertFrom-Json } catch { exit 0 }

$p5 = [double]$rl.'anthropic-ratelimit-unified-5h-utilization'
$pw = [double]$rl.'anthropic-ratelimit-unified-7d-utilization'
$max = [math]::Max($p5, $pw)
$pct = [math]::Round($max * 100)
$which = if ($p5 -ge $pw) { '5-hour' } else { 'weekly' }

$resetKey = if ($p5 -ge $pw) { 'anthropic-ratelimit-unified-5h-reset' } else { 'anthropic-ratelimit-unified-7d-reset' }
$resetEpoch = [long]($rl.$resetKey)

# STALENESS GUARD: if the recorded reset epoch is already in the past, the file is fossil
# data from a prior window. Do not warn on obsolete numbers.
if ($resetEpoch -gt 0 -and $now -ge $resetEpoch) { exit 0 }

$mins = if ($resetEpoch -gt $now) { [int](($resetEpoch - $now) / 60) } else { 0 }
$resetTxt = if ($mins -gt 0) { "resets in ~$([math]::Floor($mins/60))h$($mins%60)m" } else { "reset imminent" }

if ($pct -ge $holdPct) {
    # Arm a hold keyed to this window's reset epoch, so future turns enter CASE A.
    if ($resetEpoch -gt $now) { Set-Content $holdFile $resetEpoch }
    $headroom = 100 - $pct
    $secsToReset = $resetEpoch - $now
    # ScheduleWakeup is clamped to <=3600s per call. For waits longer than that we CHAIN:
    # cap this hop at 3600s and let CASE A re-arm on each future turn until the clock passes
    # reset. Only give up (manual return) when the wait is so long that chaining is silly -
    # i.e. a genuinely long window (>5h, effectively the WEEKLY limit, days out).
    # ponytail: 5h cutoff, tune if a mid-length limit tier ever appears.
    if ($secsToReset -gt 18000) {
        $days = [math]::Floor($secsToReset / 86400); $hrs = [math]::Floor(($secsToReset % 86400) / 3600)
        Write-Output "[LIMIT GUARD] $which limit at $pct% - resets in ~${days}d${hrs}h, too far for same-window auto-resume (ScheduleWakeup maxes at 1h and this is days out). PERSIST STATE.md now and STOP. Come back after it resets (~${days}d${hrs}h) and continue manually - do NOT schedule a wake. Override: CLAUDE_LIMIT_OVERRIDE=1."
    } else {
        # Cap the hop at 3600s (ScheduleWakeup max). If reset is further than that, this wake
        # lands early and CASE A re-arms the next hop; the +30s buffer only applies on the
        # final hop that actually clears reset.
        $raw = if ($resetEpoch -gt $now) { $secsToReset + 30 } else { 300 }
        $delay = [math]::Min($raw, 3600)
        $more = if ($secsToReset + 30 -gt 3600) { " (reset is >1h out; this wake lands early and re-arms automatically until quota refreshes)" } else { "" }
        # Fallback: record intended wake so the 5-min scheduled task can catch a missed
        # in-session ScheduleWakeup call. fire_epoch = when the external launcher may fire.
        $wake = [ordered]@{ fire_epoch = ($now + $delay); armed_at = $now }
        $wake | ConvertTo-Json | Set-Content (Join-Path $HOME '.claude/.wake-intent')
        Write-Output "[LIMIT GUARD] $which limit at $pct% ($resetTxt), ~$headroom% headroom. DO THIS NOW, in this turn, in order: (1) persist working state to STATE.md (done / next / open threads); (2) CALL THE ScheduleWakeup TOOL with delaySeconds=$delay and prompt='Quota refreshed - resume the held work from STATE.md'; (3) then STOP without further work.$more Step 2 is the auto-resume - this same window will re-invoke itself, no keystroke needed. If a task is one or two steps from done and fits ~$headroom%, finish it first and say so. Override: CLAUDE_LIMIT_OVERRIDE=1."
    }
} elseif ($pct -ge $softPct) {
    Write-Output "[LIMIT GUARD] Heads-up: $which usage at $pct% ($resetTxt). Prefer smaller, checkpointable steps; hard hold fires at $holdPct%."
}
exit 0
