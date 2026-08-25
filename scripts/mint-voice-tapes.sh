#!/bin/sh
# Mint 24 kHz little-endian PCM16 mono WAVs on a Mac (say + afconvert).
# Replay them with: ./scripts/replay-voice-tape.py
# Linux has no say/afconvert — this script is Mac-only. Not a new voice stack.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/VoiceDeskLogic/Tests/VoiceDeskLogicTests/Fixtures/voice-tapes"
mkdir -p "$DEST"

if ! command -v say >/dev/null 2>&1 || ! command -v afconvert >/dev/null 2>&1; then
    echo "mint-voice-tapes: need say + afconvert (Mac). Skip mint." >&2
    exit 2
fi

mint() {
    id="$1"
    phrase="$2"
    aiff="$DEST/$id.aiff"
    wav="$DEST/$id.wav"
    say -o "$aiff" "$phrase"
    afconvert -f WAVE -d LEI16@24000 -c 1 "$aiff" "$wav"
    rm -f "$aiff"
    echo "minted $id" >&2
}

mint show-my-latest-emails "show my latest emails"
mint my-latest-emails "my latest emails"
mint okay-show-me-my-latest-emails "okay show me my latest emails"
mint what-version-are-we-on "what version are we on"
mint what-sha-is-this "what SHA is this"
mint calendar-for-the-week "what's on my calendar for the week"
mint latest-email-from-lauren "latest email from Lauren"
mint email-from-katherine "email from Katherine"
