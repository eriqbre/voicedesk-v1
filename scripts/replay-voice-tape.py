#!/usr/bin/env python3
"""Replay minted PCM16 tapes through the same Grok realtime loop as the phone.

    ./scripts/replay-voice-tape.py

Reads XAI_API_KEY from the env or VoiceDesk/Secrets.plist. Never prints the key.
No key (or --dry-run) → exit 0 skip. Mint WAVs on a Mac first:

    ./scripts/mint-voice-tapes.sh

PCM16 24 kHz → wss://api.x.ai/v1/realtime → user transcript → EchoBargeIn
(voiceState=speaking, lastSpokenLine empty) → inbox-overview / version /
calendar / desk-person. New socket per tape — no leftover conversation.
Close 1000 must reconnect, not stayIdle.

No BlackHole. No simctl mic. No XCUITest audio-input. No new voice stack.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import socket
import ssl
import struct
import subprocess
import sys
import time
import wave
from pathlib import Path
from typing import Any
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
TAPES = ROOT / "VoiceDeskLogic/Tests/VoiceDeskLogicTests/Fixtures/voice-tapes"
MANIFEST = TAPES / "manifest.json"
SECRETS = ROOT / "VoiceDesk/Secrets.plist"
HOST = "api.x.ai"
PATH = "/v1/realtime?model=grok-voice-latest"
SAMPLE_RATE = 24000
CHUNK_FRAMES = 2400  # 100 ms, same ballpark as the phone mic tap
SILENCE_MS = 600
TAPE_TIMEOUT_S = 45.0


class WS:
    def __init__(self, raw: ssl.SSLSocket, leftover: bytes = b"") -> None:
        self.raw = raw
        self.buf = leftover

    def send_text(self, text: str) -> None:
        payload = text.encode("utf-8")
        header = bytearray([0x81])
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        elif length < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", length))
        mask = os.urandom(4)
        header.extend(mask)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.raw.sendall(header + masked)

    def send_json(self, payload: dict[str, Any]) -> None:
        self.send_text(json.dumps(payload, separators=(",", ":")))

    def recv_json(self, timeout: float) -> dict[str, Any] | None:
        deadline = time.time() + max(timeout, 0.1)
        while time.time() < deadline:
            try:
                kind, payload = self._recv_frame(deadline)
            except TimeoutError:
                continue
            except OSError:
                return None
            if kind == "close":
                return None
            if kind == "ping":
                self._send_pong(payload)
                continue
            if kind == "text":
                try:
                    return json.loads(payload.decode("utf-8"))
                except json.JSONDecodeError:
                    continue
        return None

    def wait_type(self, expected: str, timeout: float) -> dict[str, Any]:
        deadline = time.time() + timeout
        while time.time() < deadline:
            message = self.recv_json(deadline - time.time())
            if message and message.get("type") == expected:
                return message
            if message and message.get("type") == "ping":
                self.send_json(
                    {"type": "pong", "ping_timestamp": message.get("ping_timestamp") or 0}
                )
        raise SystemExit(f"error: timed out waiting for {expected}")

    def close(self) -> None:
        try:
            status = struct.pack("!H", 1000)
            header = bytearray([0x88, 0x80 | 2])
            mask = os.urandom(4)
            header.extend(mask)
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(status))
            self.raw.sendall(header + payload)
        except OSError:
            pass
        try:
            self.raw.close()
        except OSError:
            pass

    def _send_pong(self, payload: bytes) -> None:
        header = bytearray([0x8A])
        length = len(payload)
        if length < 126:
            header.append(0x80 | length)
        else:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", length))
        mask = os.urandom(4)
        header.extend(mask)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.raw.sendall(header + masked)

    def _recv_frame(self, deadline: float) -> tuple[str, bytes]:
        header = self._recvn(2, deadline)
        opcode = header[0] & 0x0F
        masked = header[1] & 0x80
        length = header[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", self._recvn(2, deadline))[0]
        elif length == 127:
            length = struct.unpack("!Q", self._recvn(8, deadline))[0]
        mask = self._recvn(4, deadline) if masked else b""
        payload = self._recvn(length, deadline)
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if opcode == 0x8:
            return "close", payload
        if opcode == 0x9:
            return "ping", payload
        if opcode == 0xA:
            return "pong", payload
        if opcode == 0x1:
            return "text", payload
        return "bin", payload

    def _recvn(self, count: int, deadline: float) -> bytes:
        while len(self.buf) < count:
            remain = max(deadline - time.time(), 0.05)
            self.raw.settimeout(remain)
            chunk = self.raw.recv(max(count - len(self.buf), 4096))
            if not chunk:
                raise OSError("socket closed")
            self.buf += chunk
        out, self.buf = self.buf[:count], self.buf[count:]
        return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Replay voice tapes against live Grok.")
    parser.add_argument("--dry-run", action="store_true", help="Skip the live socket. Exit 0.")
    args = parser.parse_args()
    # shouldSkipLive: dry-run or missing key → exit 0. Never fail CI.
    if args.dry_run or not load_api_key():
        print("skip: no XAI_API_KEY (or --dry-run). Live Grok loop not run.", file=sys.stderr)
        return 0
    return run_live()


def load_api_key() -> str | None:
    env = os.environ.get("XAI_API_KEY", "").strip()
    if env and env not in {"REPLACE_ME", "your-key-here"}:
        return env
    if not SECRETS.is_file():
        return None
    key = plist_string(SECRETS, "XAI_API_KEY")
    if key and key not in {"REPLACE_ME", "your-key-here"}:
        return key
    return None


def plist_string(path: Path, key: str) -> str | None:
    """Read one string from an XML plist. Never prints the file or the value."""
    try:
        root = ElementTree.parse(path).getroot()
    except (OSError, ElementTree.ParseError):
        return None
    nodes = list(root.find("dict") or [])
    for index, node in enumerate(nodes):
        if node.tag == "key" and (node.text or "") == key:
            if index + 1 < len(nodes) and nodes[index + 1].tag == "string":
                value = (nodes[index + 1].text or "").strip()
                return value or None
    return None


def run_live() -> int:
    catalog = load_manifest()
    missing = [item["id"] for item in catalog if not wav_path(item["id"]).is_file()]
    if missing:
        print(
            "error: mint WAVs on a Mac: ./scripts/mint-voice-tapes.sh "
            f"(missing {', '.join(missing)})",
            file=sys.stderr,
        )
        return 2

    key = load_api_key()
    if not key:
        print("skip: no XAI_API_KEY", file=sys.stderr)
        return 0

    for item in catalog:
        if not play_tape_on_fresh_socket(key, item):
            return 1

    stay = gate_json(["stay-live"])
    if stay.get("decision") != "reconnect" or stay.get("reconnect") is not True:
        print("fail: close 1000 after audio.start must reconnect, not stayIdle", file=sys.stderr)
        return 1
    print("ok: tapes accepted; close 1000 reconnects")
    return 0


def play_tape_on_fresh_socket(key: str, item: dict[str, Any]) -> bool:
    """New realtime session per tape. Prior inbox turns must not stick."""
    session = gate_json(["session-update", "--context", item.get("context") or "connected"])
    sock = connect(key)
    try:
        sock.wait_type("session.created", TAPE_TIMEOUT_S)
        sock.send_json(session)
        sock.wait_type("session.updated", TAPE_TIMEOUT_S)
        sock.send_json({"type": "input_audio_buffer.clear"})
        return play_and_assert(sock, item)
    finally:
        sock.close()


def play_and_assert(sock: WS, item: dict[str, Any]) -> bool:
    pcm = read_pcm16(wav_path(item["id"]))
    send_pcm(sock, pcm)
    user_text = ""
    response_created = False
    response_before_transcript = False
    deadline = time.time() + TAPE_TIMEOUT_S
    while time.time() < deadline:
        message = sock.recv_json(deadline - time.time())
        if message is None:
            break
        kind = parse_event(message)
        if kind["type"] == "ping":
            sock.send_json({"type": "pong", "ping_timestamp": kind.get("timestamp") or 0})
        if kind["type"] == "response.created":
            response_created = True
            if not user_text:
                response_before_transcript = True
        if kind["type"] == "userTranscript" and kind.get("text"):
            user_text = kind["text"]
        if user_text and response_created:
            break
        if user_text and kind["type"] == "response.done":
            break
    if not user_text:
        print(f"fail: {item['id']}: no user transcript from Grok", file=sys.stderr)
        return False

    decision = gate_json(
        ["decide"],
        {
            "text": user_text,
            "voiceState": "speaking",
            "lastSpokenLine": "",
            "context": item.get("context") or "connected",
        },
    )
    allowed = item.get("allowedIntents") or [item["intent"]]
    accepted = decision.get("accepted") is True and decision.get("dropped") is not True
    intent_ok = decision.get("intent") in allowed
    race = "response.created before transcript" if response_before_transcript else "transcript first"
    print(f"{item['id']}: {user_text!r} → {decision.get('intent')} ({race})")
    if not accepted or not intent_ok:
        print(
            f"fail: {item['id']}: gate dropped or wrong intent "
            f"(got {decision.get('intent')}, allowed {allowed})",
            file=sys.stderr,
        )
        return False
    return True


def load_manifest() -> list[dict[str, Any]]:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if not isinstance(data, list) or not data:
        raise SystemExit("error: voice-tapes/manifest.json is empty")
    return data


def wav_path(tape_id: str) -> Path:
    return TAPES / f"{tape_id}.wav"


def read_pcm16(path: Path) -> bytes:
    with wave.open(str(path), "rb") as handle:
        if handle.getnchannels() != 1 or handle.getsampwidth() != 2:
            raise SystemExit(f"error: {path.name} must be PCM16 mono")
        if handle.getframerate() != SAMPLE_RATE:
            raise SystemExit(f"error: {path.name} must be {SAMPLE_RATE} Hz (mint with afconvert)")
        return handle.readframes(handle.getnframes())


def send_pcm(sock: WS, pcm: bytes) -> None:
    frame_bytes = CHUNK_FRAMES * 2
    offset = 0
    while offset < len(pcm):
        chunk = pcm[offset : offset + frame_bytes]
        offset += len(chunk)
        sock.send_text(append_audio_json(chunk))
        time.sleep(CHUNK_FRAMES / SAMPLE_RATE)
    silence = b"\x00" * int(SAMPLE_RATE * (SILENCE_MS / 1000.0) * 2)
    sock.send_text(append_audio_json(silence))


def append_audio_json(pcm: bytes) -> str:
    return '{"type":"input_audio_buffer.append","audio":"%s"}' % base64.b64encode(pcm).decode(
        "ascii"
    )


def gate_json(args: list[str], payload: dict[str, Any] | None = None) -> dict[str, Any]:
    command = [
        "swift",
        "run",
        "--package-path",
        str(ROOT / "VoiceDeskLogic"),
        "VoiceTapeGate",
        *args,
    ]
    stdin = json.dumps(payload).encode() if payload is not None else None
    try:
        result = subprocess.run(command, input=stdin, capture_output=True, check=False)
    except FileNotFoundError:
        print("error: swift is required to apply EchoBargeIn", file=sys.stderr)
        raise SystemExit(2) from None
    if result.returncode != 0:
        print("error: VoiceTapeGate failed", file=sys.stderr)
        return {}
    lines = result.stdout.decode().strip().splitlines()
    if not lines:
        print("error: VoiceTapeGate produced no JSON", file=sys.stderr)
        return {}
    return json.loads(lines[-1])


def parse_event(message: dict[str, Any]) -> dict[str, Any]:
    kind = message.get("type") or ""
    if kind in {
        "conversation.item.input_audio_transcription.completed",
        "input_audio_transcription.completed",
        "conversation.item.created",
        "conversation.item.added",
    }:
        return {"type": "userTranscript", "text": user_text(message)}
    if kind == "response.created":
        return {"type": "response.created"}
    if kind == "response.done":
        return {"type": "response.done"}
    if kind == "input_audio_buffer.speech_stopped":
        return {"type": "speech_stopped"}
    if kind == "ping":
        return {"type": "ping", "timestamp": message.get("ping_timestamp") or 0}
    return {"type": kind}


def user_text(message: dict[str, Any]) -> str:
    transcript = message.get("transcript")
    if isinstance(transcript, str) and transcript.strip():
        return transcript.strip()
    item = message.get("item")
    if isinstance(item, dict) and item.get("role") == "user":
        if isinstance(item.get("transcript"), str) and item["transcript"].strip():
            return item["transcript"].strip()
        for part in item.get("content") or []:
            if not isinstance(part, dict):
                continue
            for field in ("transcript", "text"):
                value = part.get(field)
                if isinstance(value, str) and value.strip():
                    return value.strip()
    return ""


def connect(api_key: str) -> WS:
    raw = ssl.create_default_context().wrap_socket(
        socket.create_connection((HOST, 443), timeout=20),
        server_hostname=HOST,
    )
    raw.settimeout(20)
    nonce = base64.b64encode(os.urandom(16)).decode("ascii")
    request = (
        f"GET {PATH} HTTP/1.1\r\n"
        f"Host: {HOST}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {nonce}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        f"Sec-WebSocket-Protocol: xai-client-secret.{api_key}\r\n"
        "\r\n"
    )
    raw.sendall(request.encode("ascii"))
    header = b""
    while b"\r\n\r\n" not in header:
        chunk = raw.recv(4096)
        if not chunk:
            raise SystemExit("error: Grok websocket closed during handshake")
        header += chunk
    head, _, leftover = header.partition(b"\r\n\r\n")
    status = head.split(b"\r\n", 1)[0]
    if b"101" not in status:
        raise SystemExit("error: Grok websocket handshake failed")
    expected = base64.b64encode(
        hashlib.sha1((nonce + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest()
    )
    if expected not in head:
        raise SystemExit("error: Grok websocket accept mismatch")
    raw.settimeout(1.0)
    return WS(raw, leftover)


if __name__ == "__main__":
    sys.exit(main())
