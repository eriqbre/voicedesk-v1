#!/bin/sh
# Promote selected DEBUG voice-log lines into sanitized CI fixtures.
# Never commit raw Bridget / Eriq dumps.
#
# Usage:
#   tail -n 5 ~/Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl
#   ./scripts/promote-voice-regression.sh >> VoiceDeskLogic/Tests/VoiceDeskLogicTests/Fixtures/voice-regression/from-log.jsonl
#     (paste one sanitized JSON object per line on stdin, then Ctrl-D)
#
# Then add replay context if needed:
#   hadFocusedEmail, stickyFromName, assertReply, requiredNotes, forbiddenSubstrings
# General / Grok turns: intent=general, assertReply=false (do not keep Eve's spoken string).
# Desk-owned turns: keep cards + reply (or template fields) after replacing real names/emails
# with Murray Mitchell / Steve Brown / *@example.com.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/VoiceDeskLogic/Tests/VoiceDeskLogicTests/Fixtures/voice-regression"

echo "Promote into: $DEST" >&2
echo "Sanitize first. Allowed mail domain: @example.com only." >&2
echo "Reject @gmail / phones / real client names." >&2

if [ -t 0 ]; then
    echo "No stdin. Example:" >&2
    echo "  jq -c 'del(.id,.timestamp) | .assertReply = (.intent != \"general\")' \\" >&2
    echo "    ~/Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl" >&2
    exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"

if grep -Eiq '[A-Za-z0-9._%+-]+@(gmail|yahoo|icloud|me|outlook|hotmail)\.' "$tmp"; then
    echo "error: looks like a raw personal email — sanitize before promoting" >&2
    exit 1
fi
if grep -Eq '[0-9]{3}[-.][0-9]{3}[-.][0-9]{4}' "$tmp"; then
    echo "error: looks like a phone number — sanitize before promoting" >&2
    exit 1
fi

cat "$tmp"
echo "Wrote sanitized JSONL to stdout. Append to $DEST/from-log.jsonl after a final read." >&2
