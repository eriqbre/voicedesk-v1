# VoiceDesk — Testing & Branching (v1)
**Purpose:** Keep Build from the Voxa rabbit hole. Clear gates. Eriq is the **last** human validator, not the first.  
**Authority:**  
- **Automated tests** must be green on every build.  
- **Elon (this advisor)** reviews every build before Eriq sees it.  
- **Eriq** validates last; feedback drives the next agent step.  
**Companion:** `PRODUCT_REQUIREMENTS.md`

---

## 0. First principles

1. **Machines first, humans last.** If CI/automation isn’t green, no human walks it.
2. **Elon reviews before Eriq.** Catch wrong product / broken walks before burning Eriq’s time.
3. **Eriq is the final validator.** His pass ships the slice. His fail → one fix, not a PR storm.
4. **One open product PR at a time.** No parallel polish factories.
5. **Best part is no part.** Tests that don’t change a ship decision get deleted.
6. **Main is always dogfoodable.**

---

## 1. Gate order (every slice / every build)

```
[1] Cursor cloud agent builds on slice/* branch, opens PR
        ↓
[2] AUTOMATED suite must be green (required check)
        ↓
[3] ELON review — read PR, run/simulate automated evidence, do advisor walk
        ↓     Fail → reply to agent with one fix brief; do not ping Eriq
[4] HANDOFF to Eriq — short “what to do / what to tap” only
        ↓
[5] ERIQ validation walk (slice checklist, timed)
        ↓     Fail → Elon turns feedback into one fix task for the agent
[6] Squash-merge to main (Eriq or Elon after Eriq’s explicit yes)
```

**Forbidden:** Asking Eriq to test while CI is red, or before Elon has signed the review.

---

## 2. Roles

| Role | Does | Does not |
|------|------|----------|
| **Cursor agent** | Implement slice; keep automated tests green; open one PR | Merge; open sibling PRs; ask Eriq to debug |
| **Elon** | Enforce plan; expand/fix tests; review every PR; only then hand Eriq a short validation script; turn feedback into next agent brief | Dump raw CI logs on Eriq; expand scope mid-slice |
| **Eriq** | Final validation only; say pass/fail + what felt wrong | Be the first person to find “app doesn’t launch” |

---

## 3. Branching model

```
main                         # dogfood candidate; protected
  └── slice/<n>-<name>       # one active product PR
        └── fix/<desc>       # only after Elon or Eriq fail on that slice
```

### Rules
- One active `slice/*` PR. Finish or close before the next.
- Squash-merge only after **automated green + Elon review pass + Eriq validation pass**.
- No long-lived `develop` / `staging`.
- Parked PRs > 7 days: close or re-scope.

### VoiceDesk pull recipe (Mac dogfood)

After checkout, keep the committed `VoiceDesk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. It pins GoogleSignIn-iOS **9.2.0** (and GTMAppAuth 5.0.0). **Never delete** that file to “fix” a resolve — a fresh solve of `9.0.0..<10.0.0` can pick a GTMAppAuth tools-version that Xcode 16 rejects.

- If `VoiceDesk.xcodeproj` or `Package.resolved` is dirty: `git restore VoiceDesk.xcodeproj` **and** `git restore VoiceDesk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Only `git clean -f` an **untracked** `Package.resolved` that blocks checkout, then check the file out again so the committed pin returns.
- If Xcode still says `Missing package product 'GoogleSignIn'`: `xcodebuild -resolvePackageDependencies -project VoiceDesk.xcodeproj -scheme VoiceDesk` (uses the committed lockfile).
- **Signing / Development Team:** do **not** require `DEVELOPMENT_TEAM` in `Secrets.plist`. If a device build needs a team, pick it in Xcode → Signing & Capabilities. `git restore VoiceDesk.xcodeproj` may clear a picker value; just re-select Team. Putting a Team ID in Secrets is optional (inject writes it only when set). A Team ID may be committed later if we choose to — it is not a secret — not now.

### DEBUG voice interaction log (dogfood only)

Debug / Testing builds only. **Release and App Store builds compile this out** — no utterance storage, no JSONL, no ladybug UI, no upload.

Agents (Elon / Cursor / Grok Bot) read the file on disk. **Do not ask Eriq or Bridget to Copy / Share / paste.**

**Mac / Simulator (primary — zero paste)**

Each Debug Simulator turn appends JSONL here (survives rebuilds; gitignored):

```
~/Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl
```

```bash
tail -n 40 ~/Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl
# or
cat ~/Desktop/projects/voicedesk-v1/.debug/voice-log.jsonl
```

The Simulator uses `SIMULATOR_HOST_HOME` (fallback: CoreSimulator sandbox prefix) so it writes the **host** Mac path, not the app container. Eriq/Bridget just run the Debug scheme.

**Physical iPhone**

- On-device: `Documents/VoiceDesk-debug/voice-log.jsonl` (Files → On My iPhone → VoiceDesk → VoiceDesk-debug). Ladybug → **Open log folder**.
- Mac mirror without chat paste: ladybug → **Save to Files** → iCloud Drive → folder `VoiceDesk-debug`. After iCloud sync, agents read:

```
~/Library/Mobile Documents/com~apple~CloudDocs/VoiceDesk-debug/voice-log.jsonl
```

If Desktop is in iCloud, they can Save to Files into `Desktop/projects/voicedesk-v1/.debug/` instead (same primary path).

If an iCloud Documents container is later entitled, Debug also appends to that container’s `Documents/VoiceDesk-debug/` (nil-safe today — no entitlement shipped).

**What each line contains:** exact transcript, intent (general / inbox-overview / desk-person / …), sticky cleared vs reused, Gmail `q=`, cards, assistant reply, Eve vs AVSpeech.

Never commit `.debug/` or `voice-log.jsonl`.

### Slice order
1. `slice/1-ios-shell-voice-ui`
2. `slice/2-google-sync`
3. `slice/3-graph-listings`
4. `slice/4-knowledge-confidence`
5. `slice/5-actions-audit`
6. `slice/6-onboarding` (may fold earlier if tiny)

---

## 4. Comprehensive automated test plan

Automation runs on **every PR** and on **main**. Required to merge. If the cloud VM cannot run iOS Simulator, tests must still run via `xcodebuild` on a Mac pool when available; until then, Swift package / logic tests + UI fixture tests that compile on Linux where possible, plus a documented Simulator job.

### 4.1 Required suites (must all pass)

| Suite | Command (target) | Covers |
|-------|------------------|--------|
| **Unit** | `swift test` and/or Xcode unit test target | Confidence bands, offline queue, graph link helpers, draft-confirm state machine, wake/tap voice session state |
| **UI fixtures** | XCTest / XCUITest smoke | App launches; conversation mounts; each card type renders with fixtures; confirm buttons present |
| **Contract / snapshot (lightweight)** | Card view snapshot or accessibility tree asserts | Email, Listing, Person, Draft-confirm, Statute/confidence cards don’t regress layout identity |
| **Security stubs** | Unit | Confirm required before any `SendClient` mock fires; no send on draft-only |
| **Regression gate** | Same jobs as above on PR | Branch protection: all required checks green |

### 4.2 Per-slice automation additions

| Slice | Add automated coverage for |
|-------|----------------------------|
| 1 Shell | Launch smoke; card insertion API; voice session state machine; confidence UI binding |
| 2 Google | OAuth state machine mocks; sync parser tests; offline cache read; sign-out clears store |
| 3 Graph | Link inference pure functions; no neighbor-id bleed tests; claim/confirm state |
| 4 Knowledge | Confidence thresholds → firm/options/low behavior; citation required when high |
| 5 Actions | SendClient called iff confirmed; Activity log entries; failure ≠ “sent” |
| 6 Onboarding | Tour → Connect Google path; cannot reach “fake day” without connect flag |

### 4.3 What automation does **not** replace
- Real Google account behavior (Elon can smoke with stubs; Eriq validates with real account on slices 2+)
- “Feels right in the car” voice latency
- Bridget’s language of friction

### 4.4 Agent duty on every PR
PR template must include:
```
## Automated
- [ ] Unit green
- [ ] UI smoke green
- [ ] New logic covered (list tests added)
## Elon
- [ ] Pending review
## Eriq
- [ ] Not yet — wait for Elon handoff
```

---

## 5. Elon review (before Eriq)

Elon does **not** hand off until:

1. Required CI checks green on the PR head.
2. Diff matches the slice — no scope creep; no drive-by polish.
3. Walk checklist for the slice can be executed (Simulator evidence or clear repro steps).
4. Security rules for that slice hold (especially slices 2 and 5).
5. Written handoff to Eriq is **≤ 10 steps**, only what he must feel.

If Elon finds a fail: **one** reply to the cloud agent with the hole + expected fix. No Eriq ping. No new PR unless the agent can’t amend.

### Elon handoff message shape
```
Slice N ready for you.
Automated: green (link).
I checked: <one line>.
You do (≤10 min):
1. …
2. …
Pass = reply "pass" + anything weird.
Fail = reply "fail" + what broke.
```

---

## 6. Eriq validation checklists (final only)

Timebox **≤ 20 minutes**. Copy from handoff.

### Slice 1
- Cold launch to conversation
- Tap-to-talk → bubbles
- See Email / Listing / Person / Draft-confirm / Statute cards
- Draft Confirm does not fake-send
- Confidence % visible and changes tone
- No crash background/foreground

### Slice 2
- Connect Google; see real inbox/calendar/tasks
- Open email card
- Airplane mode: cached read works; write explains/queues
- Sign-out: no leftover mail bodies

### Slice 3
- Claim listing; infer+confirm from email
- Email shows related listing + people
- Listing hub graph; no wrong house

### Slice 4
- High-confidence statute → firm + cite
- Ambiguous → options + mid confidence
- Coastal pack attributed

### Slice 5
- Confirm send → real Gmail Sent
- Cancel before confirm aborts
- Calendar create confirms
- Activity log truthful on success/fail

### Slice 6
- Welcome → tour → Connect Google → first real turn

---

## 7. Feedback loop (after Eriq)

| Eriq says | Elon does |
|-----------|-----------|
| **pass** | Squash-merge (or ask Eriq to hit merge); delete branch; start next slice agent with PRD + this doc |
| **fail** + notes | One `fix/*` or amend on same PR; automated must go green; Elon re-reviews; **only then** Eriq again |
| Ambiguous feel | Elon reproduces; if product call, ask one widget question; if bug, treat as fail |

**Max loops per slice:** 2 fail cycles. Third fail → stop line; re-scope slice smaller.

---

## 8. Dogfood passes (after slices 1–5 on main)

### Pass 1 — Eriq (still last, but fuller)
Automated green on `main` + Elon confirms release candidate → Eriq runs full morning script (PRD / prior Pass 1). Fail → one fix train only.

### Pass 2 — Bridget
Only after Pass 1. Same rule.

### Pass 3 — Coastal
Android + invite + compliance. Not before.

---

## 9. Cursor agent standing orders

Include in every launch/reply:
1. Read `PRODUCT_REQUIREMENTS.md` + `TESTING_AND_BRANCHING.md`.
2. One slice PR. Expand automated tests for that slice until green.
3. Do not merge. Do not @ Eriq.
4. Wait for Elon review. If Elon requests fixes, amend same PR.
5. No polish until Pass 1.

---

## 10. Definition of done (slice)

- [ ] Automated suites green on PR
- [ ] Elon review pass + handoff sent
- [ ] Eriq validation pass
- [ ] Squash-merged; branch deleted
- [ ] Next slice only after that

## Definition of done (dogfood testing phase)

- [ ] Pass 1 + Pass 2 green
- [ ] No open slice except planned Coastal/Android
- [ ] Confirm-before-act + Activity proven on real Google writes

---

## 11. One-line brief

Automations green → Elon reviews and only then briefs Eriq → Eriq validates last → one fix loop max → merge → next slice.
