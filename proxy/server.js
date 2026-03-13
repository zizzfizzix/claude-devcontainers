'use strict';
// Claude Code credential-injection proxy.
// Reads OAuth credentials from CREDENTIALS_FILE, refreshes when needed,
// and forwards all requests to api.anthropic.com with a valid Bearer token.
//
// No npm dependencies — only Node.js built-ins.

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');

const CREDENTIALS_FILE = process.env.CREDENTIALS_FILE || '/data/credentials.json';
const PORT = parseInt(process.env.PORT || '3100', 10);
const UPSTREAM = 'api.anthropic.com';
const CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
const REFRESH_MARGIN_MS = 5 * 60 * 1000; // refresh 5 min before expiry

// Coalesce concurrent refresh attempts into a single in-flight promise.
let refreshing = null;

function readCreds() {
  try {
    return JSON.parse(fs.readFileSync(CREDENTIALS_FILE, 'utf8'));
  } catch {
    return null;
  }
}

function writeCreds(creds) {
  fs.mkdirSync(path.dirname(CREDENTIALS_FILE), { recursive: true });
  fs.writeFileSync(CREDENTIALS_FILE, JSON.stringify(creds, null, 2), { mode: 0o600 });
}

function apiRequest(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request({ hostname: UPSTREAM, ...options }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString();
        if (res.statusCode === 200) {
          resolve(JSON.parse(text));
        } else {
          reject(new Error(`Upstream ${options.path} → ${res.statusCode}: ${text}`));
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

async function doRefresh(refreshToken) {
  const body = JSON.stringify({
    grant_type: 'refresh_token',
    refresh_token: refreshToken,
    client_id: CLIENT_ID,
  });
  return apiRequest(
    { hostname: 'platform.claude.com', path: '/v1/oauth/token', method: 'POST', headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } },
    body,
  );
}

async function getToken(force = false) {
  // If a refresh is already in flight, join it.
  if (refreshing) return refreshing;

  const creds = readCreds();
  if (!creds?.claudeAiOauth) {
    throw new Error(
      'No credentials found.\n' +
      'Run: docker compose exec claude-proxy node /app/login.js',
    );
  }

  const { accessToken, refreshToken, expiresAt } = creds.claudeAiOauth;

  if (!force && Date.now() + REFRESH_MARGIN_MS < expiresAt) {
    return accessToken;
  }

  refreshing = doRefresh(refreshToken)
    .then(resp => {
      writeCreds({
        ...creds,
        claudeAiOauth: {
          ...creds.claudeAiOauth,
          accessToken: resp.access_token,
          refreshToken: resp.refresh_token,
          expiresAt: Date.now() + resp.expires_in * 1000,
        },
      });
      console.log(`[proxy] Token refreshed — expires in ${resp.expires_in}s`);
      return resp.access_token;
    })
    .finally(() => { refreshing = null; });

  return refreshing;
}

// Forward a request upstream and return { status, headers, stream }.
// Caller decides whether to pipe or buffer based on status.
function forwardUpstream(method, urlPath, inHeaders, body, token) {
  return new Promise((resolve, reject) => {
    const headers = { ...inHeaders, host: UPSTREAM, authorization: `Bearer ${token}` };
    delete headers['x-api-key']; // avoid ambiguity
    if (body.length) headers['content-length'] = body.length;

    const req = https.request({ hostname: UPSTREAM, path: urlPath, method, headers }, res => {
      resolve({ status: res.statusCode, headers: res.headers, stream: res });
    });
    req.on('error', reject);
    if (body.length) req.write(body);
    req.end();
  });
}

const server = http.createServer(async (req, res) => {
  // Health check — reports whether the server is up and whether credentials are loaded.
  // Always returns 200 so Docker healthcheck passes once the server starts,
  // even before the user has run login.js for the first time.
  if (req.method === 'GET' && req.url === '/healthz') {
    const creds = readCreds();
    const credentialsLoaded = !!creds?.claudeAiOauth;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, credentialsLoaded }));
    return;
  }

  // Buffer the request body so we can replay it on a 401 retry.
  const bodyChunks = [];
  await new Promise(done => {
    req.on('data', c => bodyChunks.push(c));
    req.on('end', done);
    req.on('error', done);
  });
  const body = Buffer.concat(bodyChunks);

  try {
    let token = await getToken();
    let up = await forwardUpstream(req.method, req.url, req.headers, body, token);

    // On 401: force-refresh once and retry.
    if (up.status === 401) {
      up.stream.resume(); // drain & discard the error body
      console.warn('[proxy] Got 401 — forcing token refresh');
      token = await getToken(true);
      up = await forwardUpstream(req.method, req.url, req.headers, body, token);
    }

    res.writeHead(up.status, up.headers);
    up.stream.pipe(res);
  } catch (err) {
    console.error('[proxy]', err.message);
    if (!res.headersSent) res.writeHead(503, { 'content-type': 'application/json' });
    if (!res.writableEnded) {
      res.end(JSON.stringify({ error: { type: 'proxy_error', message: err.message } }));
    }
  }
});

server.listen(PORT, '::', () => {
  console.log(`[proxy] Listening on :${PORT} → ${UPSTREAM}`);
  const creds = readCreds();
  if (!creds?.claudeAiOauth) {
    console.warn('[proxy] No credentials! Run login:');
    console.warn('[proxy]   docker compose exec claude-proxy node /app/login.js');
  } else {
    const exp = new Date(creds.claudeAiOauth.expiresAt).toISOString();
    console.log(`[proxy] Credentials loaded (expires ${exp})`);
  }
});
