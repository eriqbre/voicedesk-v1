#!/bin/sh
# Elon / Cursor: pull VoiceDesk dogfood JSONL. Eriq never pastes a gist id.
# Reads VOICE_DOGFOOD_GITHUB_TOKEN from VoiceDesk/Secrets.plist (or the env).
# GET /gists and picks description == "VoiceDesk dogfood voice-log".
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/VoiceDesk/Secrets.plist"
DESC="VoiceDesk dogfood voice-log"

token="${VOICE_DOGFOOD_GITHUB_TOKEN:-}"
if [ -z "$token" ] && [ -f "$PLIST" ]; then
    if command -v plutil >/dev/null 2>&1; then
        token="$(plutil -extract VOICE_DOGFOOD_GITHUB_TOKEN raw -o - "$PLIST" 2>/dev/null || true)"
    else
        token="$(python3 - "$PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    data = plistlib.load(fh)
print(data.get("VOICE_DOGFOOD_GITHUB_TOKEN") or "")
PY
)"
    fi
fi
token="$(printf '%s' "$token" | tr -d '[:space:]')"
if [ -z "$token" ]; then
    echo "error: VOICE_DOGFOOD_GITHUB_TOKEN missing in env or VoiceDesk/Secrets.plist" >&2
    exit 2
fi

export VOICE_DOGFOOD_GITHUB_TOKEN="$token"
export VOICE_DOGFOOD_GIST_DESCRIPTION="$DESC"
python3 - <<'PY'
import json, os, urllib.request

token = os.environ["VOICE_DOGFOOD_GITHUB_TOKEN"]
desc = os.environ["VOICE_DOGFOOD_GIST_DESCRIPTION"]
req = urllib.request.Request(
    "https://api.github.com/gists?per_page=100",
    headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "VoiceDesk-dogfood",
        "X-GitHub-Api-Version": "2022-11-28",
    },
)
with urllib.request.urlopen(req) as resp:
    gists = json.load(resp)
match = next(
    (
        g
        for g in gists
        if (g.get("description") or "").startswith(desc)
    ),
    None,
)
if not match:
    raise SystemExit(f"error: no gist with description {desc!r}")
gist_id = match["id"]
detail = urllib.request.Request(
    f"https://api.github.com/gists/{gist_id}",
    headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "VoiceDesk-dogfood",
        "X-GitHub-Api-Version": "2022-11-28",
    },
)
with urllib.request.urlopen(detail) as resp:
    body = json.load(resp)
files = body.get("files") or {}
file = files.get("voice-log.jsonl") or next(iter(files.values()), None)
if not file or "content" not in file:
    raise SystemExit("error: gist has no voice-log.jsonl")
print(file["content"], end="" if str(file["content"]).endswith("\n") else "\n")
PY
