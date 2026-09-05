#!/usr/bin/env python3
"""Mirror your Spotify **Liked Songs** into an ordinary playlist.

Liked Songs isn't a "context" the Spotify desktop app can shuffle on its own — which
is the only reason Flowstate needs a mirror. This copies every saved track into a
normal playlist ("Liked (Flowstate)" by default) that Spotify shuffles like any other.
Re-run it to refresh the snapshot (it *replaces* the playlist's contents, so it stays
a faithful mirror). It prints the playlist URI at the end — paste that into a
Flowstate slot.

Zero dependencies: Python 3 standard library only (no spotipy, no pip).

Auth: Spotify's PKCE flow — you need a **Client ID** but **no client secret** (a
client ID is public and safe to store). The token is cached in ~/.config/flowstate.

──────────────────────────────────────────────────────────────────────────────
ONE-TIME SETUP (≈2 min)  —  or just run  scripts/setup-liked.sh  which does this
──────────────────────────────────────────────────────────────────────────────
1. Create a free Spotify app (the only step that must be yours — it mints your own
   Client ID; Spotify no longer lets one shared app serve many users):
     • Go to  https://developer.spotify.com/dashboard  → "Create app".
     • Redirect URI: add exactly   http://127.0.0.1:8888/callback
     • APIs used: check "Web API". Save, then copy the Client ID from Settings.
       (You do NOT need the client secret — PKCE doesn't use one.)

2. Give this script the Client ID (either works):
     export SPOTIFY_CLIENT_ID='...'
   or put  SPOTIFY_CLIENT_ID=...  in  ~/.config/flowstate/sync.env

3. Run it:
     python3 scripts/sync-liked-playlist.py
   The first run opens your browser once to authorize; the token is cached, so
   later runs (including the weekly timer) are silent.
"""

import base64
import hashlib
import json
import os
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer

PLAYLIST_NAME = "Liked (Flowstate)"
PLAYLIST_DESC = "Auto-synced mirror of Liked Songs (managed by Flowstate)."
SCOPE = "user-library-read playlist-read-private playlist-modify-private playlist-modify-public"
DEFAULT_REDIRECT = "http://127.0.0.1:8888/callback"

CONFIG_DIR = os.environ.get("FLOWSTATE_CONFIG_DIR") or os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "flowstate")
ENV_FILE = os.path.join(CONFIG_DIR, "sync.env")
TOKEN_FILE = os.path.join(CONFIG_DIR, "liked-sync-token.json")

API = "https://api.spotify.com/v1"
ACCOUNTS = "https://accounts.spotify.com"


# --- Config -----------------------------------------------------------------

def load_env_file(path: str) -> None:
    """Read KEY=VALUE lines into os.environ (existing variables win)."""
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                key, value = key.strip(), value.strip().strip('"').strip("'")
                if key and key not in os.environ:
                    os.environ[key] = value
    except FileNotFoundError:
        pass


def client_id() -> str:
    cid = os.environ.get("SPOTIFY_CLIENT_ID") or os.environ.get("SPOTIPY_CLIENT_ID")
    if not cid:
        sys.exit("Missing SPOTIFY_CLIENT_ID.\nSee the setup notes at the top of this file, "
                 "or run scripts/setup-liked.sh.")
    return cid


def redirect_uri() -> str:
    return os.environ.get("SPOTIFY_REDIRECT_URI") or os.environ.get("SPOTIPY_REDIRECT_URI") or DEFAULT_REDIRECT


# --- PKCE auth --------------------------------------------------------------

def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _token_request(fields: dict) -> dict:
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(f"{ACCOUNTS}/api/token", data=body, method="POST",
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            tok = json.load(resp)
    except urllib.error.HTTPError as e:
        sys.exit(f"Spotify token request failed ({e.code}): {e.read().decode(errors='replace')[:300]}")
    tok["expires_at"] = int(time.time()) + int(tok.get("expires_in", 3600)) - 60
    return tok


def _save_token(tok: dict) -> None:
    os.makedirs(CONFIG_DIR, exist_ok=True)
    tmp = TOKEN_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(tok, fh)
    os.chmod(tmp, 0o600)
    os.replace(tmp, TOKEN_FILE)


def _load_token() -> dict | None:
    try:
        with open(TOKEN_FILE, encoding="utf-8") as fh:
            return json.load(fh)
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def authorize_interactively(cid: str, redirect: str) -> dict:
    """Open the browser once, catch the redirect on 127.0.0.1, exchange the code."""
    parsed = urllib.parse.urlparse(redirect)
    host, port = parsed.hostname or "127.0.0.1", parsed.port or 80
    verifier = _b64url(secrets.token_bytes(64))
    challenge = _b64url(hashlib.sha256(verifier.encode("ascii")).digest())
    state = secrets.token_urlsafe(16)
    url = f"{ACCOUNTS}/authorize?" + urllib.parse.urlencode({
        "client_id": cid, "response_type": "code", "redirect_uri": redirect,
        "scope": SCOPE, "state": state,
        "code_challenge_method": "S256", "code_challenge": challenge,
    })

    result: dict = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if q.get("state", [""])[0] != state:
                self.send_response(400); self.end_headers()
                self.wfile.write(b"State mismatch - please retry the sync.")
                return
            result["code"] = q.get("code", [""])[0]
            result["error"] = q.get("error", [""])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"<h2>Flowstate: Spotify authorized.</h2>You can close this tab.")

        def log_message(self, *_):
            pass

    try:
        server = HTTPServer((host, port), Handler)
    except OSError as e:
        sys.exit(f"Can't listen on {host}:{port} for the Spotify redirect ({e}). "
                 "Is another sync still running?")
    print("Opening your browser to authorize Flowstate with Spotify…")
    print(f"If nothing opens, visit:\n  {url}\n")
    webbrowser.open(url)
    server.timeout = 300
    while "code" not in result:
        server.handle_request()
        if server.timeout and not result:
            sys.exit("Timed out waiting for the Spotify authorization (5 min).")
    server.server_close()
    if result.get("error") or not result.get("code"):
        sys.exit(f"Spotify authorization failed: {result.get('error') or 'no code returned'}")

    tok = _token_request({
        "grant_type": "authorization_code", "code": result["code"],
        "redirect_uri": redirect, "client_id": cid, "code_verifier": verifier,
    })
    _save_token(tok)
    return tok


def access_token(cid: str, redirect: str) -> str:
    tok = _load_token()
    if tok and tok.get("expires_at", 0) > time.time() and tok.get("access_token"):
        return tok["access_token"]
    if tok and tok.get("refresh_token"):
        new = _token_request({"grant_type": "refresh_token",
                              "refresh_token": tok["refresh_token"], "client_id": cid})
        new.setdefault("refresh_token", tok["refresh_token"])
        _save_token(new)
        return new["access_token"]
    if not sys.stdin.isatty() and not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        sys.exit("No cached Spotify token and no way to open a browser. "
                 "Run scripts/setup-liked.sh once from a terminal.")
    return authorize_interactively(cid, redirect)["access_token"]


# --- Web API ----------------------------------------------------------------

class Spotify:
    def __init__(self, token: str):
        self.token = token

    def call(self, method: str, path: str, params: dict | None = None, body: dict | None = None):
        url = path if path.startswith("http") else f"{API}/{path.lstrip('/')}"
        if params:
            url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        for attempt in range(6):
            req = urllib.request.Request(url, data=data, method=method, headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
            })
            try:
                with urllib.request.urlopen(req, timeout=60) as resp:
                    raw = resp.read()
                    return json.loads(raw) if raw.strip() else {}
            except urllib.error.HTTPError as e:
                if e.code == 429 and attempt < 5:           # rate limited — honour Retry-After
                    time.sleep(int(e.headers.get("Retry-After", "2")) + 1)
                    continue
                if e.code in (500, 502, 503) and attempt < 5:
                    time.sleep(2 * (attempt + 1))
                    continue
                detail = e.read().decode(errors="replace")[:300]
                raise RuntimeError(f"{method} {path} failed ({e.code}): {detail}") from None
        raise RuntimeError(f"{method} {path}: gave up after retries")

    def paged(self, path: str, params: dict):
        page = self.call("GET", path, params)
        while page:
            yield from page.get("items", [])
            nxt = page.get("next")
            page = self.call("GET", nxt) if nxt else None


def find_playlist(sp: Spotify, uid: str, name: str) -> str | None:
    for pl in sp.paged("me/playlists", {"limit": 50}):
        if pl and pl.get("name") == name and pl.get("owner", {}).get("id") == uid:
            return pl["id"]
    return None


def fetch_liked_uris(sp: Spotify) -> list[str]:
    """Every saved-track URI, newest first. Skips local files (not addable)."""
    uris = []
    for item in sp.paged("me/tracks", {"limit": 50}):
        t = (item or {}).get("track") or {}
        if t.get("uri") and not t.get("is_local"):
            uris.append(t["uri"])
    return uris


def create_playlist(sp: Spotify, uid: str, name: str) -> str:
    payload = {"name": name, "public": False, "description": PLAYLIST_DESC}
    # Spotify's 2026 Web API migration retired POST /users/{id}/playlists in favour of
    # the self-scoped POST /me/playlists; try the new endpoint first, fall back once.
    try:
        return sp.call("POST", "me/playlists", body=payload)["id"]
    except RuntimeError:
        return sp.call("POST", f"users/{uid}/playlists", body=payload)["id"]


def main() -> None:
    load_env_file(os.environ.get("FLOWSTATE_ENV") or ENV_FILE)
    args = sys.argv[1:]
    name = PLAYLIST_NAME
    if "--name" in args:
        name = args[args.index("--name") + 1]
    if "--client-id" in args:
        os.environ["SPOTIFY_CLIENT_ID"] = args[args.index("--client-id") + 1]
    if "-h" in args or "--help" in args:
        print(__doc__); return

    cid, redirect = client_id(), redirect_uri()
    sp = Spotify(access_token(cid, redirect))

    me = sp.call("GET", "me")
    uid = me["id"]
    print(f"Signed in as {me.get('display_name') or uid}.")

    uris = fetch_liked_uris(sp)
    if not uris:
        sys.exit("No liked songs found — nothing to sync.")
    print(f"Found {len(uris)} liked track(s).")

    pid = find_playlist(sp, uid, name)
    if pid is None:
        pid = create_playlist(sp, uid, name)
        print(f'Created playlist "{name}".')
    else:
        print(f'Updating existing playlist "{name}".')

    # Replace contents (100 per call): the first batch replaces, the rest append.
    sp.call("PUT", f"playlists/{pid}/tracks", body={"uris": uris[:100]})
    for i in range(100, len(uris), 100):
        sp.call("POST", f"playlists/{pid}/tracks", body={"uris": uris[i:i + 100]})

    uri = f"spotify:playlist:{pid}"
    print(f'\n✓ Synced {len(uris)} tracks into "{name}".')
    print(f"  Flowstate slot target:  {uri}")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as err:
        sys.exit(f"Error: {err}")
    except KeyboardInterrupt:
        sys.exit("\nCancelled.")
