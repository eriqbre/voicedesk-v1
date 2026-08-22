# VoiceDesk (working title)

Native iPhone voice assistant for Florida realtors. Conversation is the chrome; cards are the evidence. **Voice is the product:** tap Talk and you are on a live Grok speech-to-speech loop when credentials exist.

## Source of truth

- [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md) — what to build
- [TESTING_AND_BRANCHING.md](./TESTING_AND_BRANCHING.md) — how to test, branch, and merge (read this before opening PRs)

Rename later (Voxa is taken).

## Why SwiftUI

SwiftUI is the scaffold. Style C is a conversation thread with inline cards — that maps cleanly to `ScrollView` + `LazyVStack` and keeps UIKit ceremony out. Live Grok audio uses `AVAudioEngine` + `URLSessionWebSocketTask`, ported from the [xAI iOS VoiceTesterApp](https://github.com/xai-org/xai-cookbook/tree/main/iOS/VoiceTesterApp) and the [speech-to-speech docs](https://docs.x.ai/developers/model-capabilities/audio/speech-to-speech).

## Open in Xcode / build

This cloud environment is Linux. It cannot compile or run an iOS target. Open the project on a Mac.

1. Install Xcode 16 or newer (iOS 17 SDK).
2. Open `VoiceDesk.xcodeproj`.
3. Select the **VoiceDesk** scheme and an **iPhone** simulator (or a device).
4. Signing: set your Team under the VoiceDesk target. Bundle ID is `app.voicedesk.ios`.
5. Put an xAI key on the live path (never commit it):
   - Scheme → Run → Arguments → Environment: `XAI_API_KEY` (already wired as `$(XAI_API_KEY)`), or
   - Copy `VoiceDesk/Secrets.example.plist` to `VoiceDesk/Secrets.plist` and fill `XAI_API_KEY`. `Secrets.plist` is gitignored.
6. Optional: `XAI_VOICE` (default `eve`), `XAI_VOICE_MODEL` (default `grok-voice-latest`).
7. Run (⌘R). Grant the microphone prompt. Tap **Talk** — mic streams PCM 24 kHz to Grok; Grok speaks back; transcripts land in the thread.

iPhone only. iPad / Mac Catalyst / Android are off.

### Without a key

The app shows **Connect Grok to talk**. It does **not** run a timed fake listening demo. Typed turns still use local desk-aware replies so the shell is walkable.

### Auth note (dogfood vs hardening)

`URLSessionWebSocketTask` strips the `Authorization` header on the HTTP→WS upgrade. Dogfood sends the API key the same way VoiceTesterApp does: `Sec-WebSocket-Protocol: xai-client-secret.<key>` (and still sets `Authorization: Bearer` on the request). That is acceptable for Eriq dogfood.

**Next hardening (not a slice-1 blocker):** mint a short-lived client secret from a server via `POST https://api.x.ai/v1/realtime/client_secrets` and pass that token instead of the long-lived key. See [ephemeral tokens](https://docs.x.ai/developers/model-capabilities/audio/ephemeral-tokens). `LiveGrokVoiceClient.mintRealtimeClientSecret` is implemented for that backend; the default path does not call it.

## What works in this slice

- **Live Grok speech-to-speech** when `XAI_API_KEY` is present (`GrokVoiceService` implementing `VoiceServicing`).
  - WebSocket: `wss://api.x.ai/v1/realtime?model=grok-voice-latest`
  - `session.update`: voice `eve` (configurable), VoiceDesk presence instructions, `turn_detection: server_vad`, PCM 24 kHz in/out
  - Mic → `input_audio_buffer.append`; play `response.output_audio.delta` / `response.audio.delta`
  - User + assistant transcripts mirrored into the conversation thread
  - Tap Talk again cancels: `response.cancel`, `input_audio_buffer.clear`, abort playback, close the socket
- Conversation spine (Style C): user/assistant turns with inline cards.
- Onboarding stub: welcome → short sample tour (email + listing + people graph → draft-confirm → statute/confidence → Connect Google).
- Confirm-before-act on the draft card. Confirm logs Activity and **does not** claim the email was sent.
- Voice “stop/cancel” aborts in-progress draft confirms and the live session.
- Sample cards: Email, Listing, Person, Draft-confirm, Statute/confidence, Connect Google.

Talk about anything. Cards show up when the ask is about the desk (inbox, Beach Drive, a reply, a statute). General chat stays in the thread.

`MockVoiceService` is **only** for `-ui-testing`, unit tests, and CI Simulator smoke.

## What’s stubbed

| Area | Status |
|------|--------|
| Grok voice (live loop) | **Shipped** when a key is present. Tools / desk function calls are minimal this slice (sample-desk facts live in `session.update` instructions). |
| Ephemeral token server | Client helper exists; not required for dogfood. |
| Wake word | Placeholder type + copy. Phrase is an open PRD decision. |
| Google OAuth / Gmail / Calendar / Tasks | Connect button flips a stub. No tokens, no sync. |
| Listing claim / public market data | Sample Coastal / St. Petersburg card only. No MLS. |
| Statute RAG | UI + sample Fla. Stat. § 475.278. No corpus. |
| Calendar / Task cards | Called out in replies; not drawn in this slice. |
| Silent send | Intentionally impossible. |

## Tests

| Suite | Where it runs | Command |
|-------|----------------|---------|
| Unit + UI fixtures (logic) | Linux / this VM / CI `unit-linux` on every push/PR — **merge automated gate** | `swift test --package-path VoiceDeskLogic` |
| App unit + XCUITest smoke | Local Mac, or Actions → CI → **Run workflow** (`workflow_dispatch` only; does not auto-run) | `xcodebuild test -project VoiceDesk.xcodeproj -scheme VoiceDesk -destination 'platform=iOS Simulator,name=iPhone 16'` |

This Linux cloud agent **cannot** run `xcodebuild` or the Simulator. `ios-macos` is manual because `macos-15` is expensive; it never starts on ordinary push/PR. UI smoke launches with `-ui-testing` so it uses `MockVoiceService`, not a live socket.

## Next slice

`slice/2-google-sync` — Sign in with Google, Gmail / Calendar / Tasks read, confirm-gated writes, offline cache for last-synced reads.

Hardening after dogfood: ephemeral-token backend so the long-lived xAI key never lives on device.

## Layout

```
VoiceDesk.xcodeproj      Xcode 16 project (app + unit + UI tests)
VoiceDesk/               App sources (live Grok in Voice/)
VoiceDeskLogic/          Linux-runnable domain + `swift test`
VoiceDeskTests/          Hosted app unit tests
VoiceDeskUITests/        XCUITest launch / card smoke
.github/workflows/ci.yml Linux unit + macOS Simulator
PRODUCT_REQUIREMENTS.md  Product spec (unchanged in this slice)
TESTING_AND_BRANCHING.md Gates, branches, walk checklists
```
