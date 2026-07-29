# Claude Code rate-limit proxy auto-start (sourced from PowerShell profiles).
# Starts the fail-open proxy if not already listening, then points Claude Code at it.
# OFF-SWITCH: set $env:CLAUDE_PROXY_OFF = '1' before launching a shell, or delete
#             the dot-source line from your profile.

if ($env:CLAUDE_PROXY_OFF -eq '1') { return }

$proxyScript = Join-Path $HOME '.claude\ratelimit-proxy.mjs'
$port = 8787

# Start only if nothing is already listening on the port (avoids duplicates).
$listening = $false
try {
    $listening = [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
} catch {}

if (-not $listening -and (Test-Path $proxyScript)) {
    Start-Process node -ArgumentList "`"$proxyScript`"" -WindowStyle Hidden
    # Give node up to ~2s to bind before we decide whether to route through it.
    for ($i = 0; $i -lt 10 -and -not $listening; $i++) {
        Start-Sleep -Milliseconds 200
        $listening = [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    }
}

# FAIL-SAFE: only route Claude Code through the proxy if it is actually listening.
# If the proxy is dead, leave ANTHROPIC_BASE_URL UNSET so Claude reaches the API directly
# (losing live rate-limit capture, but never losing connectivity).
if ($listening) {
    $env:ANTHROPIC_BASE_URL = "http://127.0.0.1:$port"
} else {
    Remove-Item Env:\ANTHROPIC_BASE_URL -ErrorAction SilentlyContinue
    Write-Host "[proxy-autostart] rate-limit proxy not listening on $port - running WITHOUT it (direct API). Rate-limit fields will show n/a." -ForegroundColor DarkYellow
}
