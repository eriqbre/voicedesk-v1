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
2. Open `VoiceDesk.xcodeproj`. First open resolves Swift packages (VoiceDeskLogic + [GoogleSignIn-iOS](https://github.com/google/GoogleSignIn-iOS) 9.x, pinned in `project.xcworkspace/xcshareddata/swiftpm/Package.resolved`). If Xcode shows `Missing package product 'GoogleSignIn'` or the UI stalls, run `xcodebuild -resolvePackageDependencies -project VoiceDesk.xcodeproj -scheme VoiceDesk`.
3. Select the **VoiceDesk** scheme and an **iPhone** simulator (or a device).
4. Signing: set your Team under the VoiceDesk target. Bundle ID is `app.voicedesk.ios`.
5. Put secrets on the live path (never commit them):
   - Copy `VoiceDesk/Secrets.example.plist` to `VoiceDesk/Secrets.plist` and fill `XAI_API_KEY` + `GOOGLE_CLIENT_ID`. `Secrets.plist` is gitignored and read at **runtime** for the xAI key and Google client ID.
   - For the Google URL scheme / `GIDClientID` in the app Info.plist, set `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` on the VoiceDesk target Build Settings (or in `Config/Generated/GoogleSecrets.xcconfig`). `123-abc.apps.googleusercontent.com` reverses to `com.googleusercontent.apps.123-abc`. Or run `./scripts/inject-google-secrets.sh` once by hand to write that xcconfig from Secrets.plist — it is **not** an Xcode build phase.
   - Or set scheme env `XAI_API_KEY` / `GOOGLE_CLIENT_ID`. Empty / `REPLACE_ME` reversed IDs are ignored.
6. Optional: `XAI_VOICE` (default `eve`), `XAI_VOICE_MODEL` (default `grok-voice-latest`).
7. Run (⌘R). Grant the microphone prompt. Tap **Talk** — mic streams PCM 24 kHz to Grok; Grok speaks back; transcripts land in the thread.

iPhone only. iPad / Mac Catalyst / Android are off.

### Google Cloud Console (required for real sign-in)

Without `GOOGLE_CLIENT_ID` the app **does not** pretend to be connected. Connect Google shows setup copy and stays signed out.

1. Open [Google Cloud Console](https://console.cloud.google.com/) → APIs & Services → Credentials.
2. Create an **OAuth client ID** of type **iOS**.
   - Bundle ID: `app.voicedesk.ios`
   - Copy the client ID (`….apps.googleusercontent.com`).
3. Enable APIs: **Gmail API**, **Google Calendar API**, **Google Tasks API**.
4. OAuth consent screen: add test users (your Google account) while the app is in Testing.
5. Put the client ID in `Secrets.plist` or the scheme env as `GOOGLE_CLIENT_ID`, then **rebuild**.
6. Reversed client ID URL scheme (required for the OAuth redirect):
   - Client ID `123-abc.apps.googleusercontent.com` → scheme `com.googleusercontent.apps.123-abc`
   - Set both values in Build Settings, or run `./scripts/inject-google-secrets.sh` once, then build. `Config/Info.plist` substitutes `$(GOOGLE_*)`. iOS cannot register URL types at runtime.
   - If the installed app still has `com.googleusercontent.apps.REPLACE_ME`, Connect Google fails immediately with setup copy — it will **not** call GIDSignIn and hang.
7. Scopes requested (read only this slice): `gmail.readonly`, `calendar.readonly`, `tasks.readonly`. Confirmed writes queue; they do not call Gmail send yet.

### Without an xAI key

The app shows **Connect Grok to talk**. It does **not** run a timed fake listening demo. Typed turns still use local desk-aware replies so the shell is walkable.

### Auth note (dogfood vs hardening)

`URLSessionWebSocketTask` strips the `Authorization` header on the HTTP→WS upgrade. Dogfood sends the API key the same way VoiceTesterApp does: `Sec-WebSocket-Protocol: xai-client-secret.<key>` (and still sets `Authorization: Bearer` on the request). That is acceptable for Eriq dogfood.

**Follow-up hardening (not this slice):** mint a short-lived client secret from a server via `POST https://api.x.ai/v1/realtime/client_secrets` and pass that token instead of the long-lived key. See [ephemeral tokens](https://docs.x.ai/developers/model-capabilities/audio/ephemeral-tokens). `LiveGrokVoiceClient.mintRealtimeClientSecret` is implemented for that backend; the default path does not call it.

## What works in this slice

- **Live Grok speech-to-speech** when `XAI_API_KEY` is present.
- **Connect Google first-run path:** after Talk or the sample preview, a Connect Google chip + card + coach (“Connect Google so I can see your inbox, calendar, and tasks”). Returning users who are not connected get a soft chip, not a nag wall. Playbook / offer state is in UserDefaults.
- **Real Google Sign-In** via GIDSignIn when `GOOGLE_CLIENT_ID` is set. Missing client ID fails clearly and stays signed out. Disconnect signs out and **clears** the offline cache.
- **Sync reads:** recent Gmail threads, upcoming Calendar events, open Tasks. Last-synced snapshot is cached on disk.
- Voice asks — “what’s in my inbox?”, “what’s on my calendar?”, “what tasks do I have?” — attach **real cards** from that cache when Google is connected. Sample Beach Drive mail is not used as live inbox.
- When Google is connected, Grok presence instructions swap to the synced summary. Grok is told not to invent mail that isn’t in the cache.
- Morning path: inbox ask → real email card → draft reply confirm. Confirm logs Activity as **queued, not delivered**. No silent send.
- Sample cards still exist for the first-run preview / tour (email, listing, people, draft, statute).

`MockVoiceService` and `MockGoogleAuthBackend` are **only** for `-ui-testing`, unit tests, and CI Simulator smoke. UI tests never hit live Google.

## What’s stubbed

| Area | Status |
|------|--------|
| Grok voice (live loop) | **Shipped** when a key is present. |
| Ephemeral token server | Client helper exists; follow-up hardening. |
| Wake word | Placeholder type + copy. Phrase is an open PRD decision. |
| Google OAuth | **Shipped** (GIDSignIn) when client ID is configured. |
| Gmail / Calendar / Tasks **read** | **Shipped** + offline cache. |
| Gmail / Calendar / Tasks **write** | Confirm-before-act + Activity + offline queue. Provider delivery is not implemented (no write scopes). Never reported as delivered. |
| Listing claim / public market data | Sample Coastal / St. Petersburg card only. No MLS. |
| Statute RAG | UI + sample Fla. Stat. § 475.278. No corpus. |
| Silent send | Intentionally impossible. |

## Tests

| Suite | Where it runs | Command |
|-------|----------------|---------|
| Unit + UI fixtures (logic) | Linux / this VM / CI `unit-linux` on every push/PR — **merge automated gate** | `swift test --package-path VoiceDeskLogic` |
| App unit + XCUITest smoke | Local Mac, or Actions → CI → **Run workflow** (`workflow_dispatch` only; does not auto-run) | `xcodebuild test -project VoiceDesk.xcodeproj -scheme VoiceDesk -destination 'platform=iOS Simulator,name=iPhone 16'` |

This Linux cloud agent **cannot** run `xcodebuild` or the Simulator. `ios-macos` is manual because `macos-15` is expensive; it never starts on ordinary push/PR. UI smoke launches with `-ui-testing` so it uses `MockVoiceService` and mock Google, not a live socket or GIDSignIn.

## Next slice

`slice/3-graph-listings` — email↔listing↔people graph, claim UX. Full Gmail send on confirm is slice 5.

Hardening after dogfood: ephemeral-token backend so the long-lived xAI key never lives on device.

## Layout

```
VoiceDesk.xcodeproj      Xcode 16 project (app + unit + UI tests)
VoiceDesk/               App sources (live Grok + Google Sign-In / sync). Secrets.plist stays here (gitignored). Do not put Info.plist here — Xcode’s synchronized folder would copy it into the app and collide with ProcessInfoPlistFile.
Config/Info.plist        App Info.plist (explicit PBXFileReference, INFOPLIST_FILE). URL types + GIDClientID with $(GOOGLE_*) substitution.
scripts/inject-google-secrets.sh  Optional manual helper to write Config/Generated/GoogleSecrets.xcconfig. Not a build phase.
VoiceDeskLogic/          Linux-runnable domain + `swift test`
VoiceDeskTests/          Hosted app unit tests
VoiceDeskUITests/        XCUITest launch / card smoke
.github/workflows/ci.yml Linux unit + macOS Simulator (dispatch only)
PRODUCT_REQUIREMENTS.md  Product spec
TESTING_AND_BRANCHING.md Gates, branches, walk checklists
```
