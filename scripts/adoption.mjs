// Adoption check + long-term trend: prints GitHub clone / view / star numbers and
// accumulates them past GitHub's 14-day window into a local history file.
//
// The closest honest proxy to "how many installed it" - every plugin install is a
// git clone, and GitHub reports per-day unique clones over a rolling 14-day window.
// GitHub forgets days older than 14; we don't. Each run merges the fresh day-rows
// (keyed by date, so overlaps dedupe) into ~/.claude/claude-limit-guard-adoption.json.
// Run it at least once every 14 days (a weekly cron is plenty) for gap-free history.
//
// Usage:  node scripts/adoption.mjs           show trend + record today
//         node scripts/adoption.mjs --history dump the full day-by-day table
//         gh must be installed and authed as the repo owner (traffic is owner-only).
//
// ponytail: history lives in ONE json keyed by date - dedupe is just object-assign,
//           no db, no append-log to compact. No telemetry; reads GitHub's own numbers.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const REPO = process.env.ADOPTION_REPO || 'KaushikSaurabh/resume-claude';
const STORE = path.join(os.homedir(), '.claude', 'claude-limit-guard-adoption.json');
const showHistory = process.argv.includes('--history');

function gh(endpoint) {
  try {
    const out = execFileSync('gh', ['api', endpoint], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    return JSON.parse(out);
  } catch {
    return null; // fail-open: missing gh / not-owner / no auth -> skip that line
  }
}

function load() {
  try { return JSON.parse(fs.readFileSync(STORE, 'utf8')); } catch { return { days: {}, snapshots: [] }; }
}

function save(store) {
  try { fs.writeFileSync(STORE, JSON.stringify(store, null, 1)); }
  catch (e) { console.error(`(could not write history: ${e.message})`); }
}

const repo = gh(`repos/${REPO}`);
if (!repo) {
  console.error(`Could not read ${REPO}. Is gh installed and authed? (gh auth status)`);
  process.exit(1);
}
const clones = gh(`repos/${REPO}/traffic/clones`);   // owner-only
const views = gh(`repos/${REPO}/traffic/views`);      // owner-only

// --- merge fresh day-rows into history (dedupe by date; GitHub is source of truth) ---
const store = load();
store.days ||= {};
store.snapshots ||= [];

for (const r of clones?.clones || []) {
  const d = r.timestamp.slice(0, 10);
  store.days[d] = { ...store.days[d], clones: r.count, cloneUniques: r.uniques };
}
for (const r of views?.views || []) {
  const d = r.timestamp.slice(0, 10);
  store.days[d] = { ...store.days[d], views: r.count, viewUniques: r.uniques };
}

const today = new Date().toISOString().slice(0, 10);
const snap = { date: today, stars: repo.stargazers_count, forks: repo.forks_count, watchers: repo.subscribers_count };
const last = store.snapshots[store.snapshots.length - 1];
if (!last || last.date !== today) store.snapshots.push(snap);
else store.snapshots[store.snapshots.length - 1] = snap; // overwrite same-day re-run

save(store);

// --- report ---
const dates = Object.keys(store.days).sort();
const totalClones = dates.reduce((n, d) => n + (store.days[d].clones || 0), 0);
const totalCloneUniques = dates.reduce((n, d) => n + (store.days[d].cloneUniques || 0), 0);
const span = dates.length ? `${dates[0]} .. ${dates[dates.length - 1]} (${dates.length}d tracked)` : 'no data yet';

if (showHistory) {
  console.log(`\n  ${REPO} - full history\n`);
  console.log('  date         clones  uniq   views  uniq');
  for (const d of dates) {
    const x = store.days[d];
    console.log(`  ${d}   ${String(x.clones ?? 0).padStart(5)}  ${String(x.cloneUniques ?? 0).padStart(4)}  ${String(x.views ?? 0).padStart(6)}  ${String(x.viewUniques ?? 0).padStart(4)}`);
  }
  console.log('');
  process.exit(0);
}

console.log(`\n  ${REPO}\n`);
console.log(`  stars     ${repo.stargazers_count}`);
console.log(`  forks     ${repo.forks_count}`);
console.log(`  watchers  ${repo.subscribers_count}`);
console.log(`  issues    ${repo.open_issues_count} open`);
console.log(`\n  clones  (14d)  ${clones?.count ?? 'n/a'} total, ${clones?.uniques ?? 'n/a'} unique  <- ~= installs`);
if (views) console.log(`  views   (14d)  ${views.count} total, ${views.uniques} unique`);
console.log(`\n  all-time (since tracking began)`);
console.log(`  span           ${span}`);
console.log(`  clones         ${totalClones} total, ${totalCloneUniques} unique-days  <- lower bound on installs`);
if (dates.length) {
  const peak = dates.reduce((a, d) => ((store.days[d].cloneUniques || 0) > (store.days[a].cloneUniques || 0) ? d : a), dates[0]);
  console.log(`  busiest day    ${peak}: ${store.days[peak].cloneUniques || 0} unique clones`);
}
console.log(`\n  history: ${STORE}`);
console.log(`  run 'node scripts/adoption.mjs --history' for the day-by-day table\n`);
