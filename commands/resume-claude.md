---
description: Configure auto-resume and the rate-limit hold guard (arm/off/status, custom limit %, guard on/off)
argument-hint: "[arm|off|status|limit <N>|guard on|guard off]  (no args = interactive config)"
allowed-tools: Bash, AskUserQuestion
---

The user wants to configure the limit/resume system. Arg received: `$ARGUMENTS`

## Routing
- **Empty args** → present an interactive config menu with AskUserQuestion (see below).
- `off` / `disarm` / `stop` → disarm auto-resume.
- `status` → show status of BOTH auto-resume and the guard config.
- `arm [prompt]` → arm auto-resume in the current dir (optional custom prompt).
- `limit <N>` → set the hold threshold to N percent.
- `guard off` → disable the guard entirely. `guard on` → re-enable (default 90%).
- Free text with no keyword → treat as `arm` with that text as the prompt.

## Interactive menu (empty args)
Use AskUserQuestion with these questions:
- Q1 "Auto-resume" header "Resume": options **Enable here** / **Disable** / **Leave as-is**.
- Q2 "Hold threshold" header "Limit": options **90% (default)** / **80%** / **95%** / **Guard OFF**.
Then apply the selections via the commands below. If the user picked "Enable here", ask (or infer from cwd) and arm with the default prompt unless they gave one.

## GATE PREAMBLE — before the first Bash call, output these facts (a fact-forcing gate requires them):
1. Request: configure limit-hold / auto-resume per the user's selection.
2. The commands run `claude-resume.ps1` (reads/writes `~/.claude/.resume-armed` JSON {cwd,prompt,armed_at}) and/or write `~/.claude/.limit-config` (single line: integer percent, or the literal `off`).
3. No conflict — these are the dedicated resume/limit config files.
4. Instruction: the user's `/arm-resume $ARGUMENTS` (or interactive selection).

## Commands
(Scripts live at `$env:CLAUDE_PLUGIN_ROOT\scripts\`; resume STATE stays in `$HOME\.claude\`.)
- Arm (custom prompt): `powershell -ExecutionPolicy Bypass -File "$env:CLAUDE_PLUGIN_ROOT\scripts\claude-resume.ps1" arm -Prompt "<prompt>" -Cwd "<cwd>"`
- Arm (default):        `powershell -ExecutionPolicy Bypass -File "$env:CLAUDE_PLUGIN_ROOT\scripts\claude-resume.ps1" arm -Cwd "<cwd>"`
- Disarm:               `powershell -ExecutionPolicy Bypass -File "$env:CLAUDE_PLUGIN_ROOT\scripts\claude-resume.ps1" off`
- Resume status:        `powershell -ExecutionPolicy Bypass -File "$env:CLAUDE_PLUGIN_ROOT\scripts\claude-resume.ps1" status`
- Set custom limit N:   `powershell -Command "Set-Content $HOME\.claude\.limit-config <N>"`
- Guard OFF:            `powershell -Command "Set-Content $HOME\.claude\.limit-config off"`
- Guard ON (default):   `powershell -Command "Remove-Item $HOME\.claude\.limit-config -Force -ErrorAction SilentlyContinue"`
- Read limit config:    `powershell -Command "if(Test-Path $HOME\.claude\.limit-config){Get-Content $HOME\.claude\.limit-config}else{'90 (default)'}"`

Use the current directory for -Cwd. After applying, report in one line the resulting state: auto-resume (armed where / off) AND guard (hold at N% / OFF). If auto-resume was armed, remind the user that on next refresh THIS session self-resumes via ScheduleWakeup (same window) or, if closed, the scheduled task relaunches it — and that a STATE.md should exist to guide the pickup.
