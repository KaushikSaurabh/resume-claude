// Claude Code status line — Node port of statusline.ps1 (PowerShell was ~3s/render,
// over Claude Code's timeout; node starts in ~50ms). Same output.
// Reads Status JSON from stdin; renders model, ctx meter, 5h/wk/reset, burn, cost, exit, tags.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const HOME = os.homedir();
const E = '\x1b';
const col = (c, t) => `${E}[38;5;${c}m${t}${E}[0m`;
const link = (url, t) => `${E}]8;;${url}${E}\\${t}${E}]8;;${E}\\`;
const fileUrl = p => 'file:///' + p.replace(/\\/g, '/');
const rd = p => { try { return fs.readFileSync(p, 'utf8'); } catch { return null; } };
const exists = p => { try { fs.accessSync(p); return true; } catch { return false; } };

let j = {};
try { j = JSON.parse(fs.readFileSync(0, 'utf8')); } catch {}

// ---------- LINE 1: model only (Claude Code renders the ⏵⏵ mode indicator natively) ----------
const line1 = [];
if (j.model?.display_name) line1.push(col(111, j.model.display_name));

// ---------- LINE 2: metrics ----------
const parts = [];

// Context meter: last usage block in transcript tail
let ctx = 'ctx n/a';
const tp = j.transcript_path;
if (tp && exists(tp)) {
  const lines = (rd(tp) || '').split('\n').filter(Boolean);
  for (let i = lines.length - 1; i >= 0 && i >= lines.length - 60; i--) {
    try {
      const u = JSON.parse(lines[i])?.message?.usage;
      if (u) {
        const used = (u.input_tokens||0) + (u.cache_read_input_tokens||0) + (u.cache_creation_input_tokens||0);
        const pct = Math.round(used / 200000 * 100);
        const c = pct >= 95 ? 196 : pct >= 80 ? 214 : 108;
        ctx = col(c, `ctx ${Math.round(used/1000)}k/200k ${pct}%`);
        break;
      }
    } catch {}
  }
}
parts.push(ctx);

// Rate limits from ratelimit.json
const rlRaw = rd(path.join(HOME, '.claude/ratelimit.json'));
let rlStr = col(244, '5h n/a | wk n/a | reset n/a');
if (rlRaw) {
  try {
    const rl = JSON.parse(rlRaw);
    const nowS = Math.floor(Date.now() / 1000);
    let stale = false;
    if (rl.captured_at) {
      const ageMin = (Date.now() - Date.parse(rl.captured_at)) / 60000;
      if (ageMin > 15) stale = true;
    }
    const pfx = stale ? '~' : '';
    const pctFrac = v => v != null ? Math.round(parseFloat(v) * 100) : null;
    const colFor = p => stale ? 244 : (p >= 90 ? 196 : p >= 70 ? 214 : 108);
    const p5 = pctFrac(rl['anthropic-ratelimit-unified-5h-utilization']);
    const pw = pctFrac(rl['anthropic-ratelimit-unified-7d-utilization']);
    const s5 = p5 != null ? col(colFor(p5), `${pfx}5h ${p5}%`) : col(244, '5h n/a');
    const sw = pw != null ? col(colFor(pw), `${pfx}wk ${pw}%`) : col(244, 'wk n/a');
    let sr = col(244, 'reset n/a');
    const resets = [rl['anthropic-ratelimit-unified-5h-reset'], rl['anthropic-ratelimit-unified-7d-reset']]
      .filter(Boolean).map(Number).filter(x => x > nowS).sort((a, b) => a - b);
    if (resets.length) {
      const secs = resets[0] - nowS;
      sr = col(244, `reset in ${Math.floor(secs/3600)}h${String(Math.floor((secs%3600)/60)).padStart(2,'0')}m`);
    }
    rlStr = `${s5}${col(240,' | ')}${sw}${col(240,' | ')}${sr}`;
  } catch {}
}
parts.push(rlStr);

// Burn + cost
const cost = Number(j.cost?.total_cost_usd || 0);
const durMs = Number(j.cost?.total_duration_ms || 0);
if (durMs > 0) parts.push(col(179, `burn $${(cost/(durMs/60000)).toFixed(3)}/min`));
const costCol = cost > 40 ? 196 : cost > 10 ? 214 : 149;
parts.push(col(costCol, `$${cost.toFixed(2)}`));

// Last exit code from transcript tail
if (tp && exists(tp)) {
  const lines = (rd(tp) || '').split('\n').filter(Boolean);
  for (let i = lines.length - 1; i >= 0 && i >= lines.length - 40; i--) {
    if (/"is_error"\s*:\s*true/.test(lines[i])) { parts.push(col(196, 'x1')); break; }
    if (/"type"\s*:\s*"tool_result"/.test(lines[i])) { parts.push(col(108, 'x0')); break; }
  }
}

// RESUME STATUS — persistent: always show ON/OFF + configured limit threshold.
const armed = exists(path.join(HOME, '.claude/.resume-armed'));
let limitPct = '90';
const cfg = rd(path.join(HOME, '.claude/.limit-config'));
if (cfg) { const t = cfg.split('\n')[0].trim(); limitPct = (t === 'off') ? 'off' : t; }
const armTxt = armed
  ? `RESUME ON ${limitPct === 'off' ? 'guard-off' : limitPct + '%'}`
  : 'RESUME OFF';
const armColored = col(armed ? 141 : 244, armTxt);
parts.push(armed ? link(fileUrl(path.join(HOME, '.claude/resume-launcher.log')), armColored) : armColored);

if (process.env.CLAUDE_LIMIT_OVERRIDE === '1' || exists(path.join(HOME, '.claude/.limit-override'))) {
  parts.push(col(214, 'limit:OVERRIDE'));
}

// Ponytail tag
const flag = path.join(HOME, '.claude/.ponytail-active');
if (exists(flag)) {
  const mode = (rd(flag) || '').split('\n')[0].trim();
  const tag = (!mode || mode === 'full') ? '[PONYTAIL]' : `[PONYTAIL:${mode.toUpperCase()}]`;
  parts.push(col(108, tag));
}

// Two lines: model+mode on top, metrics below.
process.stdout.on('error', () => {}); // swallow EPIPE if Claude Code closes the pipe early
try { process.stdout.write(line1.join(col(240, ' | ')) + '\n' + parts.join(col(240, ' | '))); } catch {}
