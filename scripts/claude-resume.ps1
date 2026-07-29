# Arm / disarm / check the one-shot auto-resume marker.
# Usage:
#   claude-resume.ps1 arm   [-Prompt "..."] [-Cwd "..."]   # arm: relaunch here when limits refresh
#   claude-resume.ps1 off                                   # disarm
#   claude-resume.ps1 status                                # show current state
#
# The marker (~/.claude/.resume-armed) is consumed once by resume-launcher.ps1 on refresh.

param(
    [Parameter(Position=0)][ValidateSet('arm','off','status')][string]$Action = 'status',
    [string]$Prompt,
    [string]$Cwd
)

$marker = Join-Path $HOME '.claude/.resume-armed'

switch ($Action) {
    'arm' {
        if (-not $Cwd)    { $Cwd = (Get-Location).Path }
        if (-not $Prompt) { $Prompt = "Resume the work described in STATE.md in this directory. Read it first, then continue from where it left off." }
        $obj = [ordered]@{ cwd = $Cwd; prompt = $Prompt; armed_at = ([datetimeoffset]::Now.ToString('u')) }
        $obj | ConvertTo-Json | Set-Content $marker
        Write-Host "Auto-resume ARMED. On next limit refresh, will launch: claude -p in $Cwd" -ForegroundColor Green
    }
    'off' {
        if (Test-Path $marker) { Remove-Item $marker -Force; Write-Host "Auto-resume disarmed." -ForegroundColor Yellow }
        else { Write-Host "Auto-resume was not armed." }
    }
    'status' {
        if (Test-Path $marker) {
            Write-Host "Auto-resume: ARMED" -ForegroundColor Green
            Get-Content $marker -Raw
        } else { Write-Host "Auto-resume: off" }
    }
}
