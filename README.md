# VoiceDesk (working title)

Native iPhone voice assistant for Florida realtors. Conversation is the chrome; cards are the evidence.

## Source of truth

- [PRODUCT_REQUIREMENTS.md](./PRODUCT_REQUIREMENTS.md) — what to build
- [TESTING_AND_BRANCHING.md](./TESTING_AND_BRANCHING.md) — how to test, branch, and merge (read this before opening PRs)

Rename later (Voxa is taken).

## Why SwiftUI

SwiftUI is the scaffold. Style C is a conversation thread with inline cards — that maps cleanly to `ScrollView` + `LazyVStack` and keeps UIKit ceremony out. UIKit would only help for a custom audio graph later; the Grok voice seam is already a protocol, so we can drop to AVAudioEngine without rewriting the spine.

## Open in Xcode / build

This cloud environment is Linux. It cannot compile or run an iOS target. Open the project on a Mac.

1. Install Xcode 16 or newer (iOS 17 SDK).
2. Open `VoiceDesk.xcodeproj`.
3. Select the **VoiceDesk** scheme and an **iPhone** simulator (or a device).
4. Signing: set your Team under the VoiceDesk target. Bundle ID is `app.voicedesk.ios`.
5. Run (⌘R). Grant the microphone prompt if you tap to talk.

Optional: in the VoiceDesk scheme → Run → Arguments → Environment, set `XAI_API_KEY`. The key is detected and labeled in the UI. The live Grok audio loop is still a TODO — see `Voice/GrokVoice.swift`.

iPhone only. iPad / Mac Catalyst / Android are off.

## What works in this slice

- Conversation spine (Style C): user/assistant turns with inline cards.
- Onboarding stub: welcome → short sample tour (email + listing + people graph → draft-confirm → statute/confidence → Connect Google).
- Tap-to-talk button with listening / thinking / speaking states, plus a type-a-turn field for Simulator.
- Confirm-before-act on the draft card. Confirm logs Activity and **does not** claim the email was sent.
- Voice “stop/cancel” aborts in-progress draft confirms.
- Sample cards: Email, Listing, Person, Draft-confirm, Statute/confidence, Connect Google.
- Grok voice **interfaces** pointed at current xAI endpoints (`/v1/realtime`, `/v1/stt`, `/v1/tts`).

Talk about anything. Cards show up when the ask is about the desk (inbox, Beach Drive, a reply, a statute). General chat stays in the thread.

## What’s stubbed

| Area | Status |
|------|--------|
| Grok voice STT/TTS / Voice Agent | Protocol + `LiveGrokVoiceClient` throws `notWired`. UI uses `MockVoiceService`. |
| Wake word | Placeholder type + copy. Phrase is an open PRD decision. |
| Google OAuth / Gmail / Calendar / Tasks | Connect button flips a stub. No tokens, no sync. |
| Listing claim / public market data | Sample Coastal / St. Petersburg card only. No MLS. |
| Statute RAG | UI + sample Fla. Stat. § 475.278. No corpus. |
| Calendar / Task cards | Called out in replies; not drawn in this slice. |
| Silent send | Intentionally impossible. |

## Tests

| Suite | Where it runs | Command |
|-------|----------------|---------|
| Unit + UI fixtures (logic) | Linux / this VM / CI `unit-linux` | `swift test --package-path VoiceDeskLogic` |
| App unit + XCUITest smoke | Mac + iPhone Simulator / CI `ios-macos` | `xcodebuild test -project VoiceDesk.xcodeproj -scheme VoiceDesk -destination 'platform=iOS Simulator,name=iPhone 16'` |

This Linux cloud agent **cannot** run `xcodebuild` or the Simulator. GitHub Actions `macos-15` is the iOS gate. If that runner is unavailable, treat `ios-macos` as blocked and keep `unit-linux` green.

## Next slice

`slice/2-google-sync` — Sign in with Google, Gmail / Calendar / Tasks read, confirm-gated writes, offline cache for last-synced reads.

## Layout

```
VoiceDesk.xcodeproj      Xcode 16 project (app + unit + UI tests)
VoiceDesk/               App sources
VoiceDeskLogic/          Linux-runnable domain + `swift test`
VoiceDeskTests/          Hosted app unit tests
VoiceDeskUITests/        XCUITest launch / card smoke
.github/workflows/ci.yml Linux unit + macOS Simulator
PRODUCT_REQUIREMENTS.md  Product spec (unchanged in this slice)
TESTING_AND_BRANCHING.md Gates, branches, walk checklists
```
