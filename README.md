# Resume Claude

**Automatically pause and resume Claude Code when you hit the rate limit.**

If you've ever been cut off mid-task by Claude Code's *5-hour* or *weekly* usage limit and had to babysit the terminal waiting for it to reset — this fixes that. Resume Claude shows your live usage in the status line, holds your work cleanly before you run out, and continues the **same session automatically** the moment your limit resets. No keystroke, no re-prompting, no lost context.

> Claude Code plugin. Windows / PowerShell + Node.

## What it does

- **Live rate-limit status line** — a `model` line plus `ctx | 5h% | wk% | reset | burn | cost | exit | RESUME | [PONYTAIL]`. Real Anthropic usage, colour-coded, and stale-marked (`~`) when the data is over 15 minutes old, so you always know how close you are to the limit and when it resets.
- **Hold guard** — a `UserPromptSubmit` hook that, as you approach your limit (default 90%, configurable), tells the session to persist its state and hold, instead of getting cut off mid-work.
- **No-keystroke, same-window auto-resume** — at a 5-hour hold the guard instructs the session to schedule its own wake-up, so the *same window* re-invokes itself the instant your quota refreshes. (Weekly limits, which can be days out, tell you when to come back instead.)
- **`/resume-claude`** — one command to arm/disarm auto-resume, set the limit threshold, or turn the guard off.

## Install

From Claude Code:

```
/plugin marketplace add FreyGit/resume-claude
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

- `CLAUDE_LIMIT_OVERRIDE=1` — silence the guard for the session.
- `CLAUDE_PROXY_OFF=1` — skip the proxy (rate-limit fields show `n/a`, everything else works).

## Honest limits

- Auto-resume is a behavioural contract: the hook can't call tools, it instructs the model. Robustly worded, not hard-enforced.
- The proxy is passive — it captures on traffic, so an idle window's numbers refresh only on the next message. Refresh *detection* is clock-based, so holds still release correctly.
- Nothing can inject input into an idle window from outside; the same-window, no-keystroke resume path maxes at 1 hour, which is why weekly limits can't self-wake.
