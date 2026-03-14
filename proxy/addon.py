"""
mitmproxy addon: swap dummy tokens ↔ real tokens in transit.

Claude Code manages its own credential lifecycle. This addon only:
  - Injects real tokens into outbound requests (replacing dummies)
  - Captures real tokens from OAuth responses, persists them,
    and rewrites the response to return dummies back to Claude Code
  - Scrubs real token strings from all response bodies (safety net)
"""

import json
import logging
import os
import re
import shutil
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Optional

from mitmproxy import ctx, http

log = logging.getLogger("addon")

CREDENTIALS_FILE = "/data/credentials.json"
CERT_DEST = "/certs/mitmca.pem"

DUMMY_ACCESS_TOKEN = "dummy-access-token"
DUMMY_REFRESH_TOKEN = "dummy-refresh-token"

OAUTH_HOST = "platform.claude.com"


def _mask(token: str) -> str:
    if len(token) <= 12:
        return "***"
    return f"{token[:6]}...{token[-6:]}"
OAUTH_PATH = "/v1/oauth/token"


# ---------------------------------------------------------------------------
# Credentials store
# ---------------------------------------------------------------------------

class CredentialsStore:
    def __init__(self, path: str) -> None:
        self.path = path
        self._lock = threading.Lock()
        self._creds: Optional[dict] = None
        self._load()

    def _load(self) -> None:
        if os.path.exists(self.path):
            try:
                with open(self.path) as f:
                    self._creds = json.load(f)
                log.info("Loaded credentials from %s", self.path)
            except Exception as e:
                log.warning("Failed to load credentials: %s", e)
                self._creds = None

    def save(self, creds: dict) -> None:
        with self._lock:
            self._creds = creds
            os.makedirs(os.path.dirname(self.path), exist_ok=True)
            with open(self.path, "w") as f:
                json.dump(creds, f, indent=2)
            log.info("Saved credentials to %s", self.path)

    @property
    def access_token(self) -> Optional[str]:
        with self._lock:
            return (self._creds or {}).get("access_token")

    @property
    def refresh_token(self) -> Optional[str]:
        with self._lock:
            return (self._creds or {}).get("refresh_token")

    @property
    def loaded(self) -> bool:
        with self._lock:
            return self._creds is not None


store = CredentialsStore(CREDENTIALS_FILE)


# ---------------------------------------------------------------------------
# Health HTTP server (port 3100)
# ---------------------------------------------------------------------------

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/healthz":
            body = json.dumps({"ok": True, "credentialsLoaded": store.loaded}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args) -> None:  # noqa: ANN001
        pass  # suppress request logs


def _start_health_server() -> None:
    server = HTTPServer(("", 3100), HealthHandler)
    server.serve_forever()


# ---------------------------------------------------------------------------
# Addon
# ---------------------------------------------------------------------------

class TokenSwapAddon:
    def tls_clienthello(self, data) -> None:
        """Override server address with SNI hostname.

        In transparent mode via DNS spoofing + iptables REDIRECT, SO_ORIGINAL_DST
        returns our own IP.  Use the TLS SNI to determine the real upstream host.
        """
        sni = data.client_hello.sni
        if sni and data.context.server.address:
            port = data.context.server.address[1]
            data.context.server.address = (sni, port)

    def running(self) -> None:
        # Publish the mitmproxy CA cert to the shared volume so the
        # devcontainer postStartCommand can trust it.
        confdir = os.environ.get("MITMPROXY_CONFDIR", "/data/mitmproxy")
        src = os.path.join(confdir, "mitmproxy-ca-cert.pem")
        if os.path.exists(src):
            os.makedirs(os.path.dirname(CERT_DEST), exist_ok=True)
            shutil.copy2(src, CERT_DEST)
            log.info("Copied CA cert to %s", CERT_DEST)
        else:
            log.warning("CA cert not found at %s (will retry on next run)", src)

        t = threading.Thread(target=_start_health_server, daemon=True)
        t.start()
        log.info("Health server started on :3100")

    def request(self, flow: http.HTTPFlow) -> None:
        if not store.loaded:
            return

        # Swap dummy Bearer token → real access token
        auth = flow.request.headers.get("authorization", "")
        if auth == f"Bearer {DUMMY_ACCESS_TOKEN}" and store.access_token:
            flow.request.headers["authorization"] = f"Bearer {store.access_token}"
            msg = f"[token-swap] access-token substituted for request to {flow.request.pretty_host}: {DUMMY_ACCESS_TOKEN} → {_mask(store.access_token)}"
            ctx.log.info(msg)
            flow.comment = (flow.comment + " | " if flow.comment else "") + f"access-token substituted ({DUMMY_ACCESS_TOKEN} → {_mask(store.access_token)})"

        # Swap dummy refresh_token → real refresh token on OAuth token requests
        if (
            flow.request.pretty_host == OAUTH_HOST
            and flow.request.path == OAUTH_PATH
            and flow.request.method == "POST"
        ):
            self._swap_refresh_in_request(flow)

    def response(self, flow: http.HTTPFlow) -> None:
        # Capture real tokens from OAuth response, persist, rewrite to dummies
        if (
            flow.request.pretty_host == OAUTH_HOST
            and flow.request.path == OAUTH_PATH
            and flow.request.method == "POST"
            and flow.response.status_code == 200
        ):
            self._handle_oauth_response(flow)
            return  # scrub already done inside

        # Safety net: scrub any real token strings from all other responses
        self._scrub_response(flow)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _swap_refresh_in_request(self, flow: http.HTTPFlow) -> None:
        real_refresh = store.refresh_token
        if not real_refresh:
            return
        ct = flow.request.headers.get("content-type", "")
        if "application/json" in ct:
            try:
                body = json.loads(flow.request.content)
                if body.get("refresh_token") == DUMMY_REFRESH_TOKEN:
                    body["refresh_token"] = real_refresh
                    flow.request.content = json.dumps(body).encode()
                    ctx.log.info(f"[token-swap] refresh-token substituted in OAuth request body: {DUMMY_REFRESH_TOKEN} → {_mask(real_refresh)} (JSON)")
                    flow.comment = (flow.comment + " | " if flow.comment else "") + f"refresh-token substituted ({DUMMY_REFRESH_TOKEN} → {_mask(real_refresh)}, JSON)"
            except Exception:
                pass
        elif "application/x-www-form-urlencoded" in ct:
            from urllib.parse import parse_qs, urlencode
            params = parse_qs(flow.request.content.decode(), keep_blank_values=True)
            if params.get("refresh_token") == [DUMMY_REFRESH_TOKEN]:
                params["refresh_token"] = [real_refresh]
                flow.request.content = urlencode(params, doseq=True).encode()
                ctx.log.info(f"[token-swap] refresh-token substituted in OAuth request body: {DUMMY_REFRESH_TOKEN} → {_mask(real_refresh)} (form-encoded)")
                flow.comment = (flow.comment + " | " if flow.comment else "") + f"refresh-token substituted ({DUMMY_REFRESH_TOKEN} → {_mask(real_refresh)}, form)"

    def _handle_oauth_response(self, flow: http.HTTPFlow) -> None:
        try:
            body = json.loads(flow.response.content)
        except Exception:
            return

        real_access = body.get("access_token")
        real_refresh = body.get("refresh_token")

        if real_access or real_refresh:
            new_creds = {}
            if real_access:
                new_creds["access_token"] = real_access
            if real_refresh:
                new_creds["refresh_token"] = real_refresh
            store.save(new_creds)

        # Rewrite tokens to dummies before returning to Claude Code
        changed = []
        if real_access:
            body["access_token"] = DUMMY_ACCESS_TOKEN
            changed.append("access_token")
        if real_refresh:
            body["refresh_token"] = DUMMY_REFRESH_TOKEN
            changed.append("refresh_token")

        flow.response.content = json.dumps(body).encode()
        if changed:
            parts = []
            if real_access:
                parts.append(f"access_token {_mask(real_access)} → {DUMMY_ACCESS_TOKEN}")
            if real_refresh:
                parts.append(f"refresh_token {_mask(real_refresh)} → {DUMMY_REFRESH_TOKEN}")
            ctx.log.info(f"[token-swap] OAuth response: captured + replaced — {'; '.join(parts)}")
            flow.comment = (flow.comment + " | " if flow.comment else "") + f"captured+scrubbed: {'; '.join(parts)}"

    def _scrub_response(self, flow: http.HTTPFlow) -> None:
        real_access = store.access_token
        real_refresh = store.refresh_token
        if not real_access and not real_refresh:
            return
        try:
            text = flow.response.content.decode("utf-8", errors="replace")
            scrubbed = []
            if real_access and real_access in text:
                text = text.replace(real_access, DUMMY_ACCESS_TOKEN)
                scrubbed.append(f"access_token {_mask(real_access)}")
            if real_refresh and real_refresh in text:
                text = text.replace(real_refresh, DUMMY_REFRESH_TOKEN)
                scrubbed.append(f"refresh_token {_mask(real_refresh)}")
            if scrubbed:
                flow.response.content = text.encode("utf-8")
                ctx.log.info(f"[token-swap] scrubbed from response body ({flow.request.pretty_url}): {', '.join(scrubbed)}")
                flow.comment = (flow.comment + " | " if flow.comment else "") + f"scrubbed: {', '.join(scrubbed)}"
        except Exception:
            pass


addons = [TokenSwapAddon()]
