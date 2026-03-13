'use strict';
// OAuth 2.0 + PKCE login for the Claude Code credential proxy.
//
// Usage (from inside the running proxy container):
//   docker compose exec claude-proxy node /app/login.js
//
// The script starts a local HTTP server on port 1455 (published to the host
// by docker-compose), prints the authorization URL, waits for the OAuth
// callback, exchanges the code for tokens, and saves them to CREDENTIALS_FILE.

const https = require('https');
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const CREDENTIALS_FILE = process.env.CREDENTIALS_FILE || '/data/credentials.json';
const CLIENT_ID = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';
const REDIRECT_URI = 'http://localhost:1455/callback';
const CALLBACK_PORT = 1455;

function generatePkce() {
  const verifier = crypto.randomBytes(32).toString('base64url');
  const challenge = crypto.createHash('sha256').update(verifier).digest('base64url');
  return { verifier, challenge };
}

function exchangeCode(code, verifier, state) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      grant_type: 'authorization_code',
      client_id: CLIENT_ID,
      code,
      redirect_uri: REDIRECT_URI,
      code_verifier: verifier,
      state,
    });
    const req = https.request(
      {
        hostname: 'platform.claude.com',
        path: '/v1/oauth/token',
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(body),
        },
      },
      res => {
        const chunks = [];
        res.on('data', c => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString();
          if (res.statusCode === 200) resolve(JSON.parse(text));
          else reject(new Error(`Token exchange failed ${res.statusCode}: ${text}`));
        });
      },
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function main() {
  const { verifier, challenge } = generatePkce();
  const state = crypto.randomBytes(16).toString('hex');

  const authUrl = new URL('https://claude.ai/oauth/authorize');
  authUrl.searchParams.set('client_id', CLIENT_ID);
  authUrl.searchParams.set('response_type', 'code');
  authUrl.searchParams.set('redirect_uri', REDIRECT_URI);
  authUrl.searchParams.set('code_challenge', challenge);
  authUrl.searchParams.set('code_challenge_method', 'S256');
  authUrl.searchParams.set('state', state);
  authUrl.searchParams.set('scope', 'user:inference user:profile');

  console.log('\n─────────────────────────────────────────────────');
  console.log('  Claude Code Proxy — Login');
  console.log('─────────────────────────────────────────────────\n');
  console.log('Open this URL in your browser:\n');
  console.log('  ' + authUrl.toString());
  console.log('\nWaiting for OAuth callback on port', CALLBACK_PORT, '...\n');

  await new Promise((resolve, reject) => {
    const server = http.createServer(async (req, res) => {
      try {
        const url = new URL(req.url, `http://localhost:${CALLBACK_PORT}`);
        if (url.pathname !== '/callback') {
          res.writeHead(404);
          res.end('Not found');
          return;
        }

        const code = url.searchParams.get('code');
        const returnedState = url.searchParams.get('state');

        if (!code) {
          res.writeHead(400);
          res.end('Missing authorization code');
          return;
        }
        if (returnedState !== state) {
          res.writeHead(400);
          res.end('State mismatch — possible CSRF, try again');
          return;
        }

        res.writeHead(200, { 'content-type': 'text/html' });
        res.end(
          '<html><body style="font-family:sans-serif;padding:2em">' +
          '<h2>✓ Login successful</h2>' +
          '<p>You can close this window and return to your terminal.</p>' +
          '</body></html>',
        );
        server.close();

        console.log('Exchanging authorization code for tokens...');
        const tokens = await exchangeCode(code, verifier, state);

        const creds = {
          claudeAiOauth: {
            accessToken: tokens.access_token,
            refreshToken: tokens.refresh_token,
            expiresAt: Date.now() + tokens.expires_in * 1000,
            scopes: (tokens.scope || 'user:inference user:profile').split(' '),
          },
        };

        fs.mkdirSync(path.dirname(CREDENTIALS_FILE), { recursive: true });
        fs.writeFileSync(CREDENTIALS_FILE, JSON.stringify(creds, null, 2), { mode: 0o600 });

        console.log('✓ Credentials saved to', CREDENTIALS_FILE);
        console.log(`  Access token expires in ${tokens.expires_in}s`);
        console.log('\nProxy will now serve requests. No restart needed.\n');
        resolve();
      } catch (err) {
        server.close();
        reject(err);
      }
    });

    server.on('error', reject);
    server.listen(CALLBACK_PORT, '0.0.0.0');
  });
}

main().catch(err => {
  console.error('\nLogin failed:', err.message);
  process.exit(1);
});
