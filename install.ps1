# One-time setup for the Resume Claude plugin.
# Plugins cannot edit your shell profile or register OS tasks, so run this ONCE after
# enabling the plugin. It:
#   1. Points BOTH PowerShell profiles at the plugin's proxy-autostart (sets ANTHROPIC_BASE_URL
#      so rate-limit headers get captured; fail-safe if proxy is down).
#   2. Registers the ClaudeResumeLauncher scheduled task (5-min resume fallback).
# Idempotent: safe to re-run. Uninstall with -Remove.

param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$pluginRoot = $PSScriptRoot
$autostart  = Join-Path $pluginRoot 'scripts\proxy-autostart.ps1'
$launcher   = Join-Path $pluginRoot 'scripts\resume-launcher.ps1'
$marker     = '# Resume Claude proxy autostart'
$profiles   = @(
    (Join-Path $HOME 'Documents\PowerShell\profile.ps1'),
    (Join-Path $HOME 'Documents\WindowsPowerShell\profile.ps1')
)

function Remove-Block($file) {
    if (-not (Test-Path $file)) { return }
    (Get-Content $file) | Where-Object { $_ -notmatch [regex]::Escape($marker) -and $_ -notmatch 'proxy-autostart' } | Set-Content $file
}

if ($Remove) {
    foreach ($p in $profiles) { Remove-Block $p }
    Unregister-ScheduledTask -TaskName 'ClaudeResumeLauncher' -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Resume Claude: uninstalled (profiles cleaned, task removed)." -ForegroundColor Yellow
    return
}

# 1. Profile dot-source (both PS editions)
foreach ($p in $profiles) {
    $dir = Split-Path $p -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Remove-Block $p   # avoid duplicates on re-run
    Add-Content $p "`n$marker`n. `"$autostart`""
    Write-Host "Patched profile: $p" -ForegroundColor Green
}

# 2. Scheduled task
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$launcher`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
Register-ScheduledTask -TaskName 'ClaudeResumeLauncher' -Action $action -Trigger $trigger -Settings $settings -Description 'Resume Claude resume fallback' -Force | Out-Null
Write-Host "Registered scheduled task: ClaudeResumeLauncher (every 5 min)" -ForegroundColor Green

Write-Host "`nDone. Open a NEW terminal and launch claude - rate-limit fields go live after the first message." -ForegroundColor Cyan
