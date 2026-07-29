# Resume Claude

**Automatically pause and resume Claude Code when you hit the rate limit.**

If you've ever been cut off mid-task by Claude Code's *5-hour* or *weekly* usage limit and had to babysit the terminal waiting for it to reset - this fixes that. Resume Claude shows your live usage in the status line, holds your work cleanly before you run out, and continues the **same session automatically** the moment your limit resets. No keystroke, no re-prompting, no lost context.

> Claude Code plugin. Windows (PowerShell) and macOS/Linux (bash), both + Node.
> Windows is tested and in daily use. The macOS/Linux port is new and not yet verified on a real Mac (see [Platform support](#platform-support)).

## What it does

Claude Code cuts you off when you hit a usage limit, and normally you'd sit there refreshing the terminal waiting for it to come back. Resume Claude handles all three parts of that problem:

- **You can see the limit coming.** A second status-line row shows your real usage live: context used, 5-hour and weekly percentages, a countdown to reset, burn rate, and session cost. It colours amber then red as you climb, and marks the numbers with a `~` when they're more than 15 minutes stale, so you're never guessing how much room is left.

- **It stops you cleanly before you run out.** As you near the limit (90% by default, or whatever you set), it asks Claude to write its progress to a `STATE.md` note and pause, so you stop at a clean checkpoint instead of getting killed in the middle of an edit.

- **It resumes itself, in the same window, with no keystroke.** When you hit the 5-hour wall, Claude schedules its own wake-up for the moment your quota refreshes and picks the work back up from that `STATE.md` note. You can walk away and come back to finished work. (Weekly limits can be days out, so for those it just tells you when to come back.)

- **One command to control it: `/resume-claude`.** Turn auto-resume on or off, change the limit threshold, or disable the guard entirely.

## Light by design

It adds almost nothing to your usage or your machine:

- **No extra API calls.** Usage numbers aren't polled - the local proxy reads the `anthropic-ratelimit-*` headers off responses to traffic you were already sending. It's a pass-through pipe (`req -> upstream -> res`); header capture is a side effect, not a request. Nothing is sent on your behalf.
- **Resume from a checkpoint, not a replay.** On wake it continues from the compact `STATE.md` note rather than re-feeding the whole conversation, so getting back to work doesn't burn a pile of tokens.
- **No busy-waiting.** Between limit and reset it sleeps on scheduled wake-ups; the closed-window fallback job only acts when a wake is actually overdue, so it isn't spinning in the background.
- **Fails open.** If the proxy is down or `jq` is missing, requests still go through and the guard degrades to `n/a` rather than blocking you - the tool can never become the thing standing between you and the API.

## Install

From Claude Code:

```
/plugin marketplace add KaushikSaurabh/resume-claude
/plugin install resume-claude@FreyGit
```

Then run the one-time host setup (see below) and restart your terminal.

## Why it needs a setup step

Plugins can't edit your shell profile or register OS background jobs, and two features need those:

- **Rate-limit capture** routes Claude Code's traffic through a local proxy via `ANTHROPIC_BASE_URL` (set in your shell profile). Without it, the 5h / wk / reset fields show `n/a`.
- The **resume fallback** (for when the window is fully closed) uses a Windows Scheduled Task, or a launchd job on macOS / a cron entry on Linux.

So after enabling the plugin, run the setup once for your platform.

**Windows (PowerShell):**

```powershell
& "$env:CLAUDE_PLUGIN_ROOT\install.ps1"      # or the full path to install.ps1
```

**macOS / Linux (bash):**

```bash
bash "$CLAUDE_PLUGIN_ROOT/install.sh"        # or the full path to install.sh
# needs jq for reading usage:  brew install jq   (macOS)  /  apt install jq  (Linux)
```

Then open a NEW terminal and launch `claude`. Rate-limit fields go live after the first message.

Uninstall the host changes with:

```powershell
& "...\install.ps1" -Remove       # Windows
```

```bash
bash "$CLAUDE_PLUGIN_ROOT/install.sh" --remove   # macOS / Linux
```

## Overrides

- `CLAUDE_LIMIT_OVERRIDE=1` - silence the guard for the session.
- `CLAUDE_PROXY_OFF=1` - skip the proxy (rate-limit fields show `n/a`, everything else works).

## Honest limits

- Auto-resume is a behavioural contract: the hook can't call tools, it instructs the model. Robustly worded, not hard-enforced.
- The proxy is passive - it captures on traffic, so an idle window's numbers refresh only on the next message. Refresh *detection* is clock-based, so holds still release correctly.
- Each `ScheduleWakeup` call is capped at 1 hour by the platform, so longer waits are covered by *chaining*: the guard re-arms a fresh hop every turn (with the closed-window Scheduled Task / launchd / cron job as backstop) until the window reopens. This makes the 5-hour limit fully self-resuming, no keystroke. Weekly limits can be days out, though - too many reboots, sleeps, and closed windows for an unbroken chain to survive - so those deliberately just notify you rather than promise a resume they can't reliably keep.

## Platform support

| Platform | Status |
| --- | --- |
| Windows (PowerShell) | Tested, in daily use. |
| macOS / Linux (bash) | Ported, not yet verified on a real Mac. |

The status line and the proxy are pure Node, so they behave the same everywhere. The guard, auto-resume, and installer are separate PowerShell and bash implementations of the same logic; the bash side was authored on Windows and passes syntax plus hold/release functional checks, but the usage-reading path (needs `jq`), the launchd job, and the Terminal relaunch have not been exercised on macOS yet. If you run it on a Mac, feedback and fixes are welcome. On macOS/Linux the guard needs `jq`; without it the hold/release still works but live usage reads show `n/a`.
