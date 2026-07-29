// Fail-open proxy for Claude Code: forwards all traffic to api.anthropic.com,
// captures anthropic-ratelimit-* response headers to ~/.claude/ratelimit.json.
// If ANYTHING goes wrong, the request still passes  -  header capture is best-effort only.
//
// Usage:  node ratelimit-proxy.mjs   (listens on 127.0.0.1:8787)
//         then set ANTHROPIC_BASE_URL=http://127.0.0.1:8787
//
// ponytail: single upstream host, no pooling/retry tuning  -  Node's default agent is fine
//           for one CLI. Add keep-alive only if latency measurably regresses.

import http from 'node:http';
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const PORT = process.env.CLAUDE_PROXY_PORT || 8787;
const UPSTREAM = 'api.anthropic.com';
const OUT = path.join(os.homedir(), '.claude', 'ratelimit.json');

function writeLimits(headers) {
  try {
    // Anthropic sends unified + per-window headers; grab whatever is present.
    const pick = {};
    for (const [k, v] of Object.entries(headers)) {
      if (k.toLowerCase().startsWith('anthropic-ratelimit-')) pick[k.toLowerCase()] = v;
    }
    if (Object.keys(pick).length === 0) return;
    pick.captured_at = new Date().toISOString();
    fs.writeFileSync(OUT, JSON.stringify(pick, null, 1));
  } catch { /* never let capture break anything */ }
}

const server = http.createServer((req, res) => {
  const opts = {
    host: UPSTREAM,
    port: 443,
    method: req.method,
    path: req.url,
    headers: { ...req.headers, host: UPSTREAM },
  };

  const upstream = https.request(opts, (up) => {
    writeLimits(up.headers);          // side effect, wrapped in try/catch
    res.writeHead(up.statusCode, up.headers);
    up.pipe(res);
  });

  upstream.on('error', (err) => {
    // Fail open: report a gateway error to the client but never crash the proxy.
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain' });
    res.end('proxy upstream error: ' + err.message);
  });

  req.pipe(upstream);
});

server.on('error', (e) => {
  if (e.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} already in use  -  proxy likely already running. Exiting.`);
    process.exit(0);
  }
  console.error('proxy server error:', e.message);
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`Claude ratelimit proxy on http://127.0.0.1:${PORT} -> ${UPSTREAM}`);
  console.log(`Set: ANTHROPIC_BASE_URL=http://127.0.0.1:${PORT}`);
  console.log(`Writing limits to: ${OUT}`);
});
