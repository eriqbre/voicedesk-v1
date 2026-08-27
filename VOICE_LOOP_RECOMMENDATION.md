# Voice loop recommendation (CoS review)

**To:** Elon (Chief of Staff / advisor gate)  
**From:** Grok code review of `eriqbre/voicedesk-v1`  
**Date:** 2026-08-27  
**Status:** Decision requested. Docs only. No product code in this PR.  
**Companions:** `PRODUCT_REQUIREMENTS.md` §1 Voice presence, `TESTING_AND_BRANCHING.md` §0–1

---

## Decision requested

1. Freeze all stacked feature PRs until one Talk tap stays live through speak and the next ask.
2. Implement **one** audio slice against `main` (or a thin take of #36). Do not merge #35 as-is.
3. Treat Linux `swift test` as necessary and insufficient. The walk is a real iPhone.

If you agree, the next agent brief is the implementation list in §6. If you disagree, say which constraint is wrong. Do not open another parallel voice PR.

---

## What is actually failing

Linux CI on the current voice branch is often green. The product is not.

The user-visible bug: tap Talk, Eve speaks once (often the version line), then the mic is dead. The socket later closes 1000 / idle. A second Talk tap is required. That is not a conversation.

PR #35 records the device fact on Qs iPhone 15 Pro Max at `552ef0c`: after first desk TTS, `listenArmed=true stayLive=true`, then ~21s later DidClose 1000 `stayIdle`. The tap delivered no PCM. That PR also says **do not install its tip SHA**. Phone stays on `552ef0c`.

`ios-macos` on `main` has historically been `workflow_dispatch` only and was never dispatched, so AVFoundation was not compiled in CI. That is a process hole, not the deaf-mic cause.

---

## First principles

A continuous listen-and-speak loop is one physical pipe:

1. One `AVAudioSession` in `.playAndRecord` + `.voiceChat`
2. One `AVAudioEngine`
3. One mic tap that stays installed until the user taps Stop
4. One `AVAudioPlayerNode` on that same engine
5. One WebSocket that appends 24 kHz PCM16 and plays 24 kHz PCM16

iOS echo cancellation is a HAL voice-processing unit. It is enabled with `setVoiceProcessingEnabled(true)` **while the engine is stopped**, before `installTap` / `start`. VoiceChat mode without that is not AEC.

If you tear the graph, change category mid-session, mix in a second audio client, or `setActive(false)`, the tap and the VPU die. `engine.isRunning` can stay `true` after the tap is gone. Guarding restart on `isRunning` leaves a session that looks live and hears nothing.

Two speakers cannot share the pipe. `AVSpeechSynthesizer` and `AVAudioEngine` are two audio clients. Desk TTS through the synthesizer while Grok is still capturing is why the tap goes silent after the first spoken line.

Best part is no part. Every leftover-hot latch, HAL witness, 400ms tap Task, and “first-answer” flag exists because a second speaker or a session teardown was left in the graph. Delete the second speaker. Do not add a third latch.

Reference shape: [xAI VoiceTesterApp audio engine](https://github.com/xai-org/xai-cookbook/tree/main/iOS/VoiceTesterApp) + [speech-to-speech docs](https://docs.x.ai/developers/model-capabilities/audio/speech-to-speech). Add only what a realtor day needs that the cookbook demo does not: interruption rebuild, HFP Bluetooth, background audio.

---

## What `main` does today (verified in tree)

| Part | Current | Why it kills the loop |
|------|---------|------------------------|
| Session options | `.allowBluetoothA2DP` + `.mixWithOthers` | A2DP is output-only; headset mic never joins. `mixWithOthers` downgrades the VPU. |
| `GrokVoiceAudioEngine.stop()` | Unconditional `setActive(false)` 100ms later | Restarts in that window get muted. |
| `startAudioIfNeeded()` | `guard !audio.isRunning` | After a silent HAL yank, restart is a no-op. |
| `ClientVoiceSpeech` | `AVSpeechSynthesizer` | Second speaker while the live tap is up. |
| `GrokVoiceService.speak()` | Falls through to synthesizer when live-loop gate is false | Desk replies leave the Grok player. |
| `VoiceEarcon` | `setCategory(..., .mixWithOthers)` for a click | Category change can detach a live tap. |
| `Config/Info.plist` | No `UIBackgroundModes: audio` | Lock screen ends capture. |
| Realtime `max_duration` / `timeout` | `teardown` | Long conversation ends and never returns. |
| `VoiceSocketRecovery` | `maxAutomaticReconnects = 1`, no backoff | Two cell blips end Talk. |
| `speech_started` | Always `interruptAssistant` | Eve hearing herself cancels her own line. |

Lifecycle observers for interruption, route change, `AVAudioEngineConfigurationChange`, and media-services reset are absent on `main`.

---

## What the open voice PRs are

**Do not merge both. Do not stack more features on either until the walk in §7 passes.**

### PR #36 — `cursor/fix-voice-loop-mic-dropouts-661f`

Right *shape*. Observes the five lifecycle events. Converts with `AVAudioConverter` instead of linear 48→24 (aliasing hurts server VAD). Drops A2DP-only and `mixWithOthers`. Generation-tags deferred deactivate. Reconnects with backoff. Treats “stop” as an imperative, not a substring (`I need to stop by the office` must not kill Talk).

Still more machinery than required, but pointed at real failures. Acceptable base if the dual-TTS path is deleted from it.

### PR #35 — `cursor/desk-tts-barge-in-c024`

Current dogfood branch. Not walk-ready by its own text. A week of commits undo each other: leftover-hot, HALInstallWitness, InstallTapHold, delayed tap Task, mixWithOthers / deferred-deactivate / A2DP gates. Linux is green because tests now encode those papers. Device instruction: do not flash the tip.

Do not merge #35 as the loop.

### PRs #22–#34 (echo gates, inbox synonyms, cache, cards-only, …)

Product slices on a deaf mic. Park them. Cards and synonyms do not matter if the second ask is never heard.

---

## Recommended loop (the slice)

One Talk tap until user Stop. `startCount == 1` for the whole conversation.

### Session — set once, never again until Stop

```swift
try session.setCategory(
    .playAndRecord,
    mode: .voiceChat,
    options: [.defaultToSpeaker, .allowBluetooth]
)
try session.setPreferredSampleRate(24_000)
try session.setPreferredIOBufferDuration(0.02)
try session.setActive(true)
```

No `.mixWithOthers`. No A2DP-only. No later `setCategory` from earcons or `AVSpeechSynthesizer`.

### Graph — once

1. New `AVAudioEngine` + `AVAudioPlayerNode` connected to `mainMixer` at 24 kHz float.
2. `inputNode.setVoiceProcessingEnabled(true)` while the engine is **stopped**.
3. `installTap` once. Convert with `AVAudioConverter` to PCM16 24 kHz. Send `input_audio_buffer.append`.
4. `engine.start()`; `player.play()`.
5. All sound — Grok deltas, desk lines, clicks — is `player.scheduleBuffer`.
6. After last buffer drains: do nothing. Do not `removeTap`. Do not `setActive(false)`. Do not rebuild.

### One mouth

Delete `ClientVoiceSpeech` from the live Talk path. Keep it only when the socket is down (typed / offline).

Desk replies go through the same player: text item + `response.create`, or a `session.update` that tells Eve to say that sentence. Dual-path “mute Grok, speak locally, unmute, reject leftover `response.created`” is why #35 exists. Delete it.

### Barge-in

`speech_started` → `player.stop(); player.play()` and `response.cancel` only if Grok is speaking. Do not rebuild the tap. Echo of Eve is the VPU’s job, not a string-overlap gate.

### Rebuild only for real HAL death

- `AVAudioEngineConfigurationChange`
- `mediaServicesWereReset`
- interruption `.ended` with `.shouldResume`

Not: TTS drain, route `categoryChange` / `override` (those are our own session setup echoing back), app-active by itself.

Watchdog allowed: if `wantsCapture && engine.isRunning && no tap energy for ~1.5s`, `removeTap` + `installTap` on the **same** running engine. Do not increment start count. Do not deactivate the session.

### Socket is not audio

Reconnect the WebSocket on 1000 / drop / `max_duration` without touching the engine. Replace `maxAutomaticReconnects = 1` with a small exponential budget. Never reconnect after user Stop.

### Plist

Add `UIBackgroundModes = audio`. Keep the mic usage string.

### Stop intent

Bare “stop” / “cancel” / “never mind” ends Talk. Substring match inside a sentence does not.

---

## Implementation list (next agent, one PR)

Files on the live path:

- `VoiceDesk/Voice/GrokVoiceAudioEngine.swift`
- `VoiceDesk/Voice/GrokVoiceService.swift`
- `VoiceDesk/Voice/ClientVoiceSpeech.swift` (dead on live loop)
- `VoiceDesk/Voice/VoiceEarcon.swift` (click through the live player only)
- `Config/Info.plist`
- `VoiceDeskLogic` socket / stop-intent helpers only as needed

Do:

- Session options as above; enable VPU while stopped.
- Lifecycle observers limited to §6 rebuild list.
- `AVAudioConverter` for capture.
- Generation-tag any deferred deactivate, or delete deferred deactivate.
- One mouth: all live playback on the player node.
- Socket reconnect independent of the graph.
- Background audio mode.
- Stop as an imperative.

Do not:

- Merge #35.
- Add leftover-hot / witness / inject-bit machinery.
- Add honesty gates that fail a SHA by grepping comments.
- Touch inbox synonyms, cache merge, or cards-only in the same PR.
- Ask Eriq to walk until this list is implemented and Linux unit is green **and** Elon has signed the phone walk.

Preferred base: `main`, pulling only the useful bits of #36 (lifecycle, converter, session options, stop-intent, socket backoff). Not the #35 test theater.

---

## Walk that decides pass (Elon first, then Eriq)

Real iPhone. One Talk tap. No second tap. Debug scheme so the voice log exists; do not ask Eriq to paste it.

1. “What version is this?” — full spoken line, no cut.
2. Immediately: “What’s in my inbox?” — heard as a new turn on the same tap. `startCount` stays 1.
3. AirPods mid-sentence — mic returns without a new Talk tap.
4. Incoming call, dismiss — mic returns.
5. Lock, unlock — still listening.
6. Talk past realtime `max_duration` — socket reconnects; engine does not rebuild.
7. “I need to stop by the office” — session stays up. Bare “stop” ends it.

If step 2 fails, the graph was torn after TTS. Fix that before any card or synonym work.

Pass = Elon writes the ≤10 step Eriq handoff from `TESTING_AND_BRANCHING.md` §5. Fail = one fix on the same PR.

---

## What this recommendation is not

- Not a merge of #35 or #36.
- Not a product rename, pricing, or GTM change.
- Not permission to open a second product PR while this loop is red.
- Not a claim that Linux 412/0 means the phone can hear.

---

## Elon signed 2026-08-27 (read the PR, not a paste)

Accepted (matches the simple one-pipe loop already in flight on #35):
- One session playAndRecord + voiceChat + defaultToSpeaker/BT. No mixWithOthers. No A2DP-only.
- One AVAudioEngine, VP on while stopped, one tap, one AVAudioPlayerNode.
- Live Talk is Eve only. Delete ClientVoiceSpeech / desk-TTS first-audio from the live session. write→playPCM16. Never AVSpeechSynthesizer.speak().
- After last buffer drains: do nothing. Rebuild only on AVAudioEngineConfigurationChange or media-services reset.
- Barge-in: player.stop(); player.play() + cancel in-flight if Grok is speaking.

Rejected:
- Freeze #35 / “#35 is not the loop” / implement §6 on main or thin #36. Stay on #35. Do not merge #36.
- Silent-tap watchdog reinstall after drain (that is the 552ef0c hole).
- interruption.ended / route / app-active rebuilds as part of this slice (already .none on 5bcfbd7).
- Walk in §7 as the ship gate. Linux + honest sim first. Do not ask Eriq to walk. Phone hold 5bcfbd7.
- UIBackgroundModes, stop-intent substring, socket-backoff as this slice. Later, not now.

## Elon
- [x] REJECT: freeze stacked PRs; one audio slice; #35 not the loop
- [x] ACCEPT: one mouth (no AVSpeechSynthesizer.speak() on live Talk)
- [x] REJECT: walk in §7 is the ship gate
- [x] REJECT: Next brief: implement §6 on main / thin #36

## Eriq
- [ ] Not yet — wait for Elon handoff after the implementation PR is green
