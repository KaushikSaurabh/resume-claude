#!/usr/bin/env bash
# One-time setup for the Resume Claude plugin (macOS/Linux twin of install.ps1).
# Plugins cannot edit your shell rc or register OS jobs, so run this ONCE after enabling
# the plugin. It:
#   1. Sources the proxy-autostart from your shell rc (sets ANTHROPIC_BASE_URL for capture).
#   2. Registers a 5-min resume-fallback job: launchd (macOS) or cron (Linux).
# Idempotent: safe to re-run. Uninstall with --remove.
set -u

PLUGIN_ROOT="$(cd "$(dirname "$0")" && pwd)"
AUTOSTART="$PLUGIN_ROOT/scripts/proxy-autostart.sh"
LAUNCHER="$PLUGIN_ROOT/scripts/resume-launcher.sh"
MARKER="# Resume Claude proxy autostart"
LABEL="com.resume-claude.launcher"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Pick the shell rc: prefer zsh on macOS, else bash.
if [ -n "${ZDOTDIR:-}" ]; then RC="$ZDOTDIR/.zshrc"
elif [ "$(basename "${SHELL:-}")" = "zsh" ] || [ "$(uname)" = "Darwin" ]; then RC="$HOME/.zshrc"
else RC="$HOME/.bashrc"; fi

remove_block() {
  [ -f "$RC" ] || return 0
  # Drop the marker line and any line sourcing proxy-autostart.sh.
  grep -v -F "$MARKER" "$RC" 2>/dev/null | grep -v 'proxy-autostart.sh' > "$RC.tmp" && mv "$RC.tmp" "$RC"
}

is_mac() { [ "$(uname)" = "Darwin" ]; }

if [ "${1:-}" = "--remove" ]; then
  remove_block
  if is_mac; then
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
  else
    ( crontab -l 2>/dev/null | grep -v -F "$LAUNCHER" ) | crontab - 2>/dev/null || true
  fi
  echo "Resume Claude: uninstalled (shell rc cleaned, job removed)."
  exit 0
fi

# 1. Shell rc source line
remove_block   # avoid duplicates on re-run
{ printf '\n%s\n' "$MARKER"; printf '[ -f "%s" ] && source "%s"\n' "$AUTOSTART" "$AUTOSTART"; } >> "$RC"
echo "Patched shell rc: $RC"

# 2. Resume-fallback job (every 5 min)
if is_mac; then
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$LAUNCHER</string>
  </array>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><false/>
</dict>
</plist>
PLISTEOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST" 2>/dev/null || true
  echo "Registered launchd job: $LABEL (every 5 min)"
else
  # Linux: cron entry, deduped.
  ( crontab -l 2>/dev/null | grep -v -F "$LAUNCHER"; printf '*/5 * * * * /bin/bash %s\n' "$LAUNCHER" ) | crontab -
  echo "Registered cron job (every 5 min)"
fi

echo ""
echo "Done. Open a NEW terminal and launch claude - rate-limit fields go live after the first message."
echo "Tip: install jq if you don't have it (brew install jq) - the guard needs it to read usage."
