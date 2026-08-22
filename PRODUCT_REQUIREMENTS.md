# VoiceDesk — Product Requirements (v1)
**Working title:** VoiceDesk (rename later; Voxa is taken)  
**Audience for this doc:** Grok Build / engineering agents building the app from scratch  
**Platform:** Native iPhone first (iOS). Android required before Coastal office-wide rollout; not in v1 dogfood.  
**Primary voice:** xAI Grok voice (conversational speech in + speech out)  
**Owner intent:** First-principles native voice assistant for Florida realtors — not a port of an existing web desk.

---

## 1. Vision

A realtor opens the app and talks. The app talks back. While it speaks, it draws the right UI: the email, the listing, the people, the calendar, the task, the statute — and how they connect.

The product is **one continuous voice loop** over:
1. Florida real estate expertise (statutes + local + broker rules)
2. The agent’s Google world (Gmail, Calendar, Tasks)
3. Listings & people (claimed/inferred “mine” + public market data)
4. On-the-fly **conversation + content cards** UI

If voice works but the screen doesn’t show the evidence, it’s broken.  
If the screen works but voice isn’t primary, it’s broken.

---

## 2. Rollout & users

| Phase | Who | Goal |
|-------|-----|------|
| **Dogfood** | Bridget (listing agent, Coastal Properties) | Daily indispensable use |
| **Broker** | Coastal Properties agents | Invite/gated; Coastal compliance pack live; **Android required before this phase** |
| **Open FL** | Any Florida realtor | Self-serve; additional broker packs later |

**Day-one design customer:** Bridget / Coastal Tampa Bay context.  
**Do not** optimize v1 for anonymous statewide acquisition.

---

## 3. Jobs to be done

### Primary (dead if fails)
Open app → speak → get a correct spoken answer **and** see the interconnected cards (email ↔ listing ↔ people ↔ calendar ↔ tasks).

### Supporting
- Answer Florida / county / local RE questions with **visible confidence** driving tone.
- Run the day from voice: inbox, calendar, tasks (Google).
- Know “my listings” and related communications.
- Take actions with **show → confirm → act** and a full audit trail.
- Work in the car: wake word when app open; tap otherwise; offline cache for reads.

---

## 4. Interaction model (locked) — “Style C”

### Spine
- **Conversation thread** is the primary chrome (user + assistant turns).
- **Content cards** appear inline as evidence and actions.
- Voice narrates; cards prove. Assistant must not invent facts that aren’t on a card or in a cited source.

### Voice
- **Grok voice** for STT + TTS conversational loop.
- App open: optional **wake word**; otherwise **tap/hold to talk**.
- Open can begin listening after onboarding permissions.

### Core screens / cards (v1)
| Card | Behavior |
|------|----------|
| **Inbox list** | Modern mail list; filters: All / Listings / Clients / Partners; voice can jump to a thread |
| **Email detail** | Full message card + Related listing + Connected people |
| **Listing hub** | Public/mine listing hero + related emails + next showing + open tasks + people |
| **Calendar** | Event card and/or day context linked to listings/people |
| **Task** | Task card linked to listing/email when known |
| **Person / contact** | Best-in-class contact row/card; call/message affordances |
| **Draft / Confirm** | Before any send/write: show exact action; Confirm & Send / Edit |
| **Statute / confidence** | Plain-language + source; **confidence meter visible**; drives firm vs options |
| **Activity / audit** | Log of every write/send/schedule |

### UX quality bar
- Modern consumer mail (Spark/Shortwave-class email cards)
- Zillow/Realtor-grade listing presentation
- Familiar iOS patterns (HIG) for navigation, permissions, system feel
- Light theme default; purple accent acceptable as brand (replaceable)

**Reference flows:** conversation + cards (see design exploration C / C2–C6).

---

## 5. Agency & safety (locked)

**Not** silent full agency.

1. User requests an action → app **shows** what will happen (draft card) → user **confirms** → app executes.
2. Future/scheduled actions → show schedule → confirm → execute at time → log.
3. **Full audit trail** of all writes (email send, calendar create/update/delete, task create/complete, listing claim, etc.). User can review Activity.
4. Voice “stop/cancel” should abort in-progress confirmation flows.

High-stakes default: money, contracts, mass email still use the same confirm card (never auto-send).

---

## 6. Data & integrations (v1)

### Google (required)
- Sign in with Google
- Gmail (read + send on confirm)
- Google Calendar (read + create/update on confirm)
- Google Tasks (read + create/complete on confirm)

### Listings
- **No MLS in v1** (Stellar later).
- Public listing sources via **licensed/allowed APIs or feeds** (product intent: Realtor.com / Zillow-class market data — implement only via permitted sources; no ToS-violating scrape-as-architecture).
- **My listings:** infer candidates from Gmail + Calendar; user confirms/claims; user can add by address/voice.

### Knowledge
- Florida statutes (statewide)
- County / local rules relevant to Coastal / Bridget’s markets (Pinellas, Hillsborough, Pasco as priority)
- **Broker compliance pack:** ingest Coastal-specific rules provided as documents; versioned; attributable in answers

### Confidence model (law / compliance)
- Every law/compliance answer exposes **confidence 0–100%** on a card.
- **High (e.g. ≥85%):** firm guidance tone; still not a substitute for a lawyer/broker-of-record.
- **Mid:** present options / uncertainty; user decides.
- **Low:** say what’s unknown; don’t bluff.
- Prefer citations (statute section, doc name) on the card.

### Out of scope for v1
- Facebook / Instagram posting & campaigns (phase 2 after core)
- Stellar MLS / Matrix / Wolf
- CRM (Follow Up Boss etc.)
- Android (until Coastal office rollout)
- Silent send without confirm
- TestFlight “marketing” before Bridget dogfood passes

---

## 7. Offline

- **Read:** last-synced mail, calendar, tasks, listing cards available offline.
- **Voice actions:** queue until online; surface queued state on Activity.
- Clear offline banner; don’t fake live Grok if network required for generation.

---

## 8. Onboarding (locked)

1. Fresh conversation: welcome; offer a **short tour**.
2. Tour uses **sample cards** to show conversation + email/listing/people graph.
3. Tour ends on **Connect Google** card (required for real usefulness).
4. Mic permission; wake-word tip.
5. First real turn on their data (< few minutes total).

No multi-page settings wizard.

---

## 9. Non-functional requirements

- Privacy-first: Google tokens secured; no pasting secrets into logs; audit log is user-visible product data.
- Performance: first spoken response feeling snappy on good network; cards stream in as ready.
- Reliability: failed sends stay as failed drafts on Activity; never report “sent” without provider success.
- Accessibility: Dynamic Type, VoiceOver basics on cards.
- App Store: clear microphone purpose string; privacy nutrition labels honest about Google + voice processing (xAI).

---

## 10. Success criteria

### Bridget dogfood “pass”
- Completes a real morning: ask about inbox/calendar by voice; open an email and see related listing/people; claim/confirm a listing; send one confirmed email; schedule one calendar item.
- Law question shows confidence card and cites source.
- She does not bail to Gmail to finish the thought for those flows.

### Coastal-ready
- Invite path for Coastal agents
- Coastal compliance pack answers attributable
- Android build available
- Audit trail acceptable to broker ops

---

## 11. Suggested build slices (for Grok Build)

1. **Shell:** iOS app, conversation UI, mic, Grok voice loop, wake word + tap.
2. **Cards framework:** email, listing, person, calendar, task, draft-confirm, statute-confidence, activity.
3. **Google OAuth + sync** (Gmail/Calendar/Tasks) + offline cache.
4. **Graph links:** email↔listing↔people↔events↔tasks (inference + claim UX).
5. **Public listing lookup** (permitted source) + “add/claim mine.”
6. **Knowledge:** FL statutes + local + Coastal pack RAG; confidence UI.
7. **Actions:** confirm cards → Google writes; scheduling; Activity log.
8. **Onboarding** conversational tour → Connect Google.

---

## 12. Explicit non-goals / delete list

- Rebuilding the old web “desk chrome” as home screen
- PR mill / polish without dogfood
- Capacitor wrapper as the product (this is native iPhone)
- Marketing campaign builder in v1
- Inventing MLS fields or neighbor listing bleed

---

## 13. Open decisions (name only)

- Final product name (replace VoiceDesk)
- Exact public listing data vendor (must be licensed)
- Wake word phrase / branding
- Confidence thresholds exact numbers (defaults: firm ≥85, options 50–84, refuse/ask <50)

---

## 14. One-line brief for Grok Build

Build a native iPhone app where Grok voice is the primary UI: a conversation thread that spawns best-in-class email, listing, people, calendar, and task cards (and confirm/audit cards for actions), connected as a graph; Google-only productivity; Florida + local + Coastal compliance knowledge with visible confidence; Bridget dogfood first; Android later for Coastal rollout; no silent sends; no MLS in v1.
