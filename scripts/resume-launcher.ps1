# Auto re-launcher: when rate limits refresh AND a resume is ARMED, start ONE fresh
# headless `claude -p` session pointed at saved state. NOT a true resume of a paused
# session - it launches new context that reads your STATE/resume note.
#
# Armed by writing ~/.claude/.resume-armed as JSON: {"cwd":"...","prompt":"...","armed_at":"..."}
# One-shot: the marker is DELETED before launch so a crash/loop can never re-fire it.
# Run every ~5 min via scheduled task.
#
# ponytail: "refreshed" = binding window utilization fell below 0.5. Coarse but a scheduled
#           task re-checks in 5 min, and the marker is one-shot, so a missed edge self-heals.

$ErrorActionPreference = 'SilentlyContinue'
$marker = Join-Path $HOME '.claude/.resume-armed'
$rlFile = Join-Path $HOME '.claude/ratelimit.json'
$log    = Join-Path $HOME '.claude/resume-launcher.log'
$intent = Join-Path $HOME '.claude/.wake-intent'

# FALLBACK GATE (#3): the PRIMARY resume is the in-session ScheduleWakeup, which on success
# deletes .wake-intent when the hold releases. This launcher only acts as a safety net for a
# CLOSED window where that call could never fire. So: require .wake-intent to still exist AND
# be clearly overdue (fire_epoch >5 min past) before doing anything. If .wake-intent is gone,
# the in-session resume happened - do nothing.
if (Test-Path $intent) {
    try {
        $wi = Get-Content $intent -Raw | ConvertFrom-Json
        $now = [datetimeoffset]::UtcNow.ToUnixTimeSeconds()
        if ($now -lt ([long]$wi.fire_epoch + 300)) { exit 0 }   # not yet overdue -> let in-session wake handle it
        Remove-Item $intent -Force                               # overdue: consume it, we are the fallback now
        Add-Content $log "$([datetimeoffset]::Now.ToString('u')) FALLBACK wake-intent overdue, launcher taking over"
    } catch {}
}

if (-not (Test-Path $marker)) { exit 0 }           # not armed -> nothing to do
if (-not (Test-Path $rlFile)) { exit 0 }           # no usage data -> wait

try { $arm = Get-Content $marker -Raw | ConvertFrom-Json } catch { exit 0 }
try { $rl  = Get-Content $rlFile -Raw | ConvertFrom-Json } catch { exit 0 }

$p5 = [double]$rl.'anthropic-ratelimit-unified-5h-utilization'
$pw = [double]$rl.'anthropic-ratelimit-unified-7d-utilization'
$max = [math]::Max($p5, $pw)

# Limits considered refreshed when the binding window is back under 50%.
if ($max -ge 0.5) { exit 0 }

# --- Fire once. Delete marker FIRST so we can never double-launch. ---
$cwd    = if ($arm.cwd)    { $arm.cwd }    else { $HOME }
$prompt = if ($arm.prompt) { $arm.prompt } else { "Resume the work described in STATE.md in this directory. Read it first, then continue from where it left off." }
Remove-Item $marker -Force

$stamp = [datetimeoffset]::Now.ToString('u')
Add-Content $log "$stamp LAUNCH cwd=$cwd util=$([math]::Round($max*100))% prompt=$($prompt.Substring(0,[math]::Min(80,$prompt.Length)))"

# Resume the ACTUAL prior session (its full transcript/context), not a blank one.
# `claude --continue` re-attaches to the most recent session in $cwd and re-plays its
# history, then we hand it the resume prompt so it picks up the thread. This is the
# same-session continuity the user wants (unsaved in-conversation state is on disk in
# the transcript .jsonl, so --continue restores it). Falls back to a plain pwsh window.
# Opens in a NEW visible terminal window so the user can see/interact with it.
$psCmd = "Set-Location -LiteralPath '$cwd'; claude --continue '$($prompt -replace "'","''")'"
try {
    Start-Process -FilePath 'wt.exe' -ArgumentList @('new-tab','--title','Claude Resume','pwsh','-NoExit','-Command',$psCmd) -ErrorAction Stop
    Add-Content $log "$stamp OK resumed via --continue in new terminal tab"
} catch {
    try {
        Start-Process -FilePath 'pwsh' -ArgumentList @('-NoExit','-Command',$psCmd) -WorkingDirectory $cwd
        Add-Content $log "$stamp OK resumed via --continue in pwsh window"
    } catch {
        Add-Content $log "$stamp ERROR $($_.Exception.Message)"
    }
}
exit 0
