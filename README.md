# Resume Claude

**Automatically pause and resume Claude Code when you hit the rate limit.**

If you've ever been cut off mid-task by Claude Code's *5-hour* or *weekly* usage limit and had to babysit the terminal waiting for it to reset - this fixes that. Resume Claude shows your live usage in the status line, holds your work cleanly before you run out, and continues the **same session automatically** the moment your limit resets. No keystroke, no re-prompting, no lost context.

> Claude Code plugin. Windows / PowerShell + Node.

## What it does

Claude Code cuts you off when you hit a usage limit, and normally you'd sit there refreshing the terminal waiting for it to come back. Resume Claude handles all three parts of that problem:

- **You can see the limit coming.** A second status-line row shows your real usage live: context used, 5-hour and weekly percentages, a countdown to reset, burn rate, and session cost. It colours amber then red as you climb, and marks the numbers with a `~` when they're more than 15 minutes stale, so you're never guessing how much room is left.

- **It stops you cleanly before you run out.** As you near the limit (90% by default, or whatever you set), it asks Claude to write its progress to a `STATE.md` note and pause, so you stop at a clean checkpoint instead of getting killed in the middle of an edit.

- **It resumes itself, in the same window, with no keystroke.** When you hit the 5-hour wall, Claude schedules its own wake-up for the moment your quota refreshes and picks the work back up from that `STATE.md` note. You can walk away and come back to finished work. (Weekly limits can be days out, so for those it just tells you when to come back.)

- **One command to control it: `/resume-claude`.** Turn auto-resume on or off, change the limit threshold, or disable the guard entirely.

## Install

From Claude Code:

```
/plugin marketplace add KaushikSaurabh/resume-claude
/plugin install resume-claude@FreyGit
```

Then run the one-time host setup (see below) and restart your terminal.

## Why it needs a setup step

Plugins can't edit your PowerShell profile or register OS scheduled tasks, and two features need those:

- **Rate-limit capture** routes Claude Code's traffic through a local proxy via `ANTHROPIC_BASE_URL` (set in your profile). Without it, the 5h / wk / reset fields show `n/a`.
- The **resume fallback** (for when the window is fully closed) uses a Windows Scheduled Task.

So after enabling the plugin, run the setup once:

```powershell
& "$env:CLAUDE_PLUGIN_ROOT\install.ps1"      # or the full path to install.ps1
```

Then open a NEW terminal and launch `claude`. Rate-limit fields go live after the first message.

Uninstall the host changes with:

```powershell
& "...\install.ps1" -Remove
```

## Overrides

- `CLAUDE_LIMIT_OVERRIDE=1` - silence the guard for the session.
- `CLAUDE_PROXY_OFF=1` - skip the proxy (rate-limit fields show `n/a`, everything else works).

## Honest limits

- Auto-resume is a behavioural contract: the hook can't call tools, it instructs the model. Robustly worded, not hard-enforced.
- The proxy is passive - it captures on traffic, so an idle window's numbers refresh only on the next message. Refresh *detection* is clock-based, so holds still release correctly.
- Nothing can inject input into an idle window from outside; the same-window, no-keystroke resume path maxes at 1 hour, which is why weekly limits can't self-wake.
