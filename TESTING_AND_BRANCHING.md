# VoiceDesk — Testing & Branching (v1)
**Purpose:** Keep Build from turning into the Voxa rabbit hole (PR mill, merge-without-walk, endless polish).  
**Authority:** Eriq is the only merge gate for product behavior. CI is necessary, not sufficient.  
**Companion:** `PRODUCT_REQUIREMENTS.md`

---

## 0. First principles (non-negotiable)

1. **Walk > merge.** If a human did not exercise the change on a device (or Simulator for pure UI), it does not land on `main`.
2. **One open product PR at a time** per slice. No parallel “while you wait” hygiene PRs.
3. **Best part is no part.** If a test or branch doesn’t change a ship decision, delete it.
4. **Dogfood is the product test.** Bridget’s day is the acceptance suite for “ready.”
5. **CI catches regressions; walks catch wrong products.** Both required. Neither alone.
6. **Main is always dogfoodable.** Broken main = stop the line.

---

## 1. What went wrong on Voxa (so we don’t repeat it)

| Failure | Rule that prevents it |
|---------|------------------------|
| Dozens of PRs merged while the real walk (195) sat | One slice PR; no merge of “also-ran” work |
| Cloud agents + human merges raced | Agents open PRs; **only Eriq merges** after a walk checklist |
| “Review clean” treated as ship | Review ≠ walk. Walk checklist is mandatory |
| Auth/spend holes shipped then patched forever | Security slices have a **hard walk** before merge; no “merge then fix” |
| Testing phase never ended | Each slice has **exit criteria**. When met, stop. Next slice or ship. |
| Polish PRs (timing, chrome) ate weeks | Polish only after Dogfood Pass 1. Parked by default. |

---

## 2. Branching model

```
main                    # always runnable dogfood candidate
  └── slice/<n>-<name>  # one active product slice (PR → walk → merge)
        └── fix/<desc>  # optional: only if walk finds a hole on that slice
```

### Rules
- **`main`:** protected. No direct push for agents. Squash-merge only after walk.
- **`slice/*`:** exactly **one** active slice branch + PR. Finish or close before opening the next.
- **`fix/*`:** short-lived, branched from the slice under walk (or from `main` if hotfix). Same walk bar scaled to the fix.
- **No** long-lived `develop`, `staging`, or `release` trains in v1. They hide rot.
- **No** stacking 5 agent PRs “for later.” Close or park.

### Slice order (aligned to PRD §11)
1. `slice/1-ios-shell-voice-ui` — conversation + cards + voice shell  
2. `slice/2-google-sync` — OAuth + Gmail/Calendar/Tasks + offline cache  
3. `slice/3-graph-listings` — claim/infer listings + related cards  
4. `slice/4-knowledge-confidence` — FL/local/Coastal pack + confidence UI  
5. `slice/5-actions-audit` — confirm-before-act + Activity log (real writes)  
6. `slice/6-onboarding` — welcome tour → Connect Google (may land earlier if tiny)

**Do not start slice N+1 until slice N is on `main` and Pass criteria below are green.**

---

## 3. Merge gate (the algorithm)

For every PR into `main`:

```
1. Question: Does this slice move Bridget closer to Pass 1?
   No → close or park. Do not merge.
2. Delete: Any extra commits that aren’t load-bearing?
3. CI green (build + unit tests for touched logic).
4. Eriq walk checklist for THAT slice (below) — timed, written.
5. Squash-merge. Delete branch.
6. Tag dogfood build if iOS: voicedesk-dogfood-YYYYMMDD
```

**Forbidden merges**
- “CI green, merge to keep moving”
- Security-sensitive changes without the security walk
- Agent follow-up PRs opened while a slice walk is unfinished
- Anything that expands scope mid-slice without a new slice PR

---

## 4. What you test, and when

### 4.1 Layers (keep thin)

| Layer | Who | When | What |
|-------|-----|------|------|
| **Unit** | Agent/CI | Every PR | Pure logic: confidence bands, graph link helpers, offline queue |
| **UI smoke** | Agent/CI or Simulator | Every PR | App launches; conversation renders; cards mount with fixtures |
| **Slice walk** | **Eriq** | Before merge | Scripted 10–20 min checklist for that slice |
| **Dogfood pass** | **Eriq then Bridget** | After slices 2–5 land | Real morning / real listing — see §5 |
| **Broker gate** | Eriq + Coastal | Before office rollout | Invite path, compliance pack, Android exists |

If a test doesn’t map to a row above, delete it.

### 4.2 Slice walk checklists (you run these)

Copy into the PR comment and check off. **Timebox: 20 minutes.** If you can’t finish, the slice is too big — split.

#### Slice 1 — Shell + voice UI
- [ ] Cold launch < 3s to conversation UI (Simulator or device)
- [ ] Tap-to-talk shows listening state; release/end shows a user bubble
- [ ] Assistant turn can insert **Email**, **Listing**, **Person**, **Draft-confirm**, **Statute/confidence** fixture cards
- [ ] Draft-confirm shows Confirm / Edit; Confirm does not silently “send” (mock OK)
- [ ] Statute card shows a **visible confidence %** and firm vs options behavior changes with the number
- [ ] No crash on rotate / background / foreground
- [ ] README build steps work on your Mac

**Exit:** Merge. Stop. Do not open polish PRs.

#### Slice 2 — Google sync
- [ ] Connect Google from the card; scopes: Gmail, Calendar, Tasks
- [ ] Inbox list shows real threads; open one email card
- [ ] Calendar shows today’s events; Tasks show open items
- [ ] Airplane mode: last-synced cards readable; action attempt queues or explains offline
- [ ] Disconnect / sign-out clears local cache of mail bodies (no leftover account bleed)

**Exit:** Merge only after the above on a **device or Simulator signed into your Google**.

#### Slice 3 — Graph + listings
- [ ] Claim a listing by address (voice or UI)
- [ ] Infer candidate from a real Gmail thread → confirm/dismiss
- [ ] Email detail shows **Related listing** + **Connected people** when linked
- [ ] Listing hub shows related emails / next event / tasks / people
- [ ] No neighbor-address bleed (wrong house on a card)

**Exit:** Merge.

#### Slice 4 — Knowledge + confidence
- [ ] Ask a high-confidence FL statute question → firm tone + cite on card
- [ ] Ask an ambiguous question → options, not fake certainty; mid confidence shown
- [ ] Coastal compliance doc answer attributes the broker pack
- [ ] Confidence meter always visible on law/compliance cards

**Exit:** Merge.

#### Slice 5 — Actions + audit
- [ ] “Email X…” → draft card → Confirm sends for real → appears in Gmail Sent
- [ ] “Undo/cancel” before confirm aborts
- [ ] Schedule a calendar event → confirm → exists in Google Calendar
- [ ] Activity log shows each write with timestamp + result
- [ ] Failed send shows failed on Activity — never “sent” on failure

**Exit:** Merge. This is the last hard gate before Bridget Pass 1.

#### Slice 6 — Onboarding (if separate)
- [ ] Fresh install: welcome → sample tour → Connect Google → first real turn
- [ ] Skip-tour path still forces Google before pretending to know the day
- [ ] Under a few minutes to first useful answer

---

## 5. Dogfood passes (world-class bar)

### Pass 1 — Eriq (before Bridget’s phone)
**When:** After slices 1–5 on `main`.  
**Timebox:** One real morning block (≤ 90 min). One retry if fail. No third.

Script:
1. Open app; ask what’s on calendar today by voice.
2. Ask about one real email; confirm related listing/people cards.
3. Claim/confirm one listing you care about.
4. Send one **confirmed** email that you would have sent anyway.
5. Ask one FL disclosure / Coastal compliance question; check confidence card.
6. Do **not** open Gmail to finish those five. If you bail, Pass 1 fails.

**Fail →** one fix branch from `main`, walk that fix, merge, **one** retry.  
**Fail twice →** stop feature work; only Pass-1 blockers.

### Pass 2 — Bridget dogfood
**When:** Pass 1 green.  
**Bar:** She completes her version of the script without you narrating around bugs.  
**Fail →** same one-fix rule. Her language of friction becomes the backlog — not a PR storm.

### Pass 3 — Coastal office
**When:** Pass 2 green + Android build + invite path + compliance pack.  
**Not before.**

---

## 6. Agent / Cursor rules (encode in every Build prompt)

1. Open **one** PR for the active slice. Do not open sibling PRs.
2. Do not merge. Do not ask to merge. Eriq merges after walk.
3. If you find a P0 outside the slice (auth, data loss), **stop and report** — do not “also fix” in the same PR unless Eriq says so.
4. No polish PRs (timing, chrome, haptics) until Pass 1.
5. PR description must include: **Walk checklist** (copy from this doc) + **Out of scope**.
6. If CI flake blocks merge, fix flake or retry — do not disable gates.

---

## 7. Security / money walks (hard stops)

Treat as their own mini-slice if they appear:
- OAuth / token storage / callback URLs
- Anything that can send email or mint model spend without confirm
- Cross-user cache bleed

**Walk:** Prove a stolen/shared URL cannot create a session; prove Confirm is required before send; prove spend has a cap or confirm.  
**No merge** on “we’ll rate-limit later.”

---

## 8. Cadence (keep cycle time high without the factory)

| Cadence | Action |
|---------|--------|
| Per slice | Agent builds → CI → Eriq 20-min walk → squash merge → delete branch |
| Daily (dogfood) | One Pass 1 attempt or real use — not five micro-PRs |
| Weekly | Kill parked PRs older than 7 days or explicitly re-scope |
| Never | Merge Friday night “just to clear the queue” without a walk |

---

## 9. Definition of “testing phase complete”

Testing phase for v1 dogfood is **done** when:
- [ ] Pass 1 green once
- [ ] Pass 2 green once (Bridget)
- [ ] No open `slice/*` except the next planned Coastal/Android work
- [ ] Activity log + confirm-before-act proven on real Google writes

Everything after that is product iteration — not an unbounded “testing phase.”

---

## 10. One-line brief for Cursor

One slice branch, one PR, CI green, Eriq walks the slice checklist on a device, then squash-merge; no parallel polish; Pass 1/2 are the only acceptance tests that matter; stop when they pass.
