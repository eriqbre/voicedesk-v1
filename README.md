# VoiceDesk

A voice-first help desk built with **Next.js 16** (App Router), **React 19**, **TypeScript**, and **Tailwind CSS v4**.

VoiceDesk lets a support agent dictate (or type) a customer request. The request is
transcribed in the browser via the Web Speech API, then sent to the server where it is
turned into a structured, auto-triaged ticket (subject + priority derived from the
content). Tickets flow through an `open → in progress → resolved` lifecycle.

## Features

- **Voice capture** — live speech-to-text using the browser Web Speech API, with a
  graceful fallback to typing when the API is unavailable.
- **Auto-triage** — the server derives a subject line and a priority (`low` / `medium`
  / `high`) from the transcript.
- **Ticket queue** — real-time list with status badges, priority, channel, and
  one-click status transitions.
- **JSON API** — `GET/POST /api/tickets` and `PATCH /api/tickets/:id`.

## Getting started

```bash
npm ci        # install exact dependencies from the lockfile
npm run dev   # start the dev server on port 3000
```

Then open the app at `http://localhost:<port>` (port `3000` by default).

Other useful scripts:

```bash
npm run build      # production build
npm run start      # run the production build
npm run lint       # ESLint
npm run typecheck  # tsc --noEmit
```

## API

All examples assume the dev server base URL is in `$APP_URL`:

```bash
export APP_URL="http://localhost:$PORT"   # PORT defaults to 3000
```

Create a ticket:

```bash
curl -s -X POST "$APP_URL/api/tickets" \
  -H 'Content-Type: application/json' \
  -d '{"transcript":"I was charged twice and need a refund urgently","channel":"voice"}'
```

List tickets:

```bash
curl -s "$APP_URL/api/tickets"
```

Update a ticket's status:

```bash
curl -s -X PATCH "$APP_URL/api/tickets/TCK-1002" \
  -H 'Content-Type: application/json' \
  -d '{"status":"resolved"}'
```

## Architecture

| Path | Responsibility |
| --- | --- |
| `src/app/page.tsx` | Server component that loads initial tickets and renders the dashboard. |
| `src/components/VoiceDesk.tsx` | Client dashboard: mic capture, transcript, ticket queue. |
| `src/hooks/useSpeechRecognition.ts` | Web Speech API wrapper hook. |
| `src/app/api/tickets/route.ts` | List + create tickets. |
| `src/app/api/tickets/[id]/route.ts` | Update ticket status. |
| `src/lib/tickets.ts` | In-memory ticket store + auto-triage logic. |

> The ticket store is in-memory and resets when the server restarts. Swap
> `src/lib/tickets.ts` for a real database (e.g. Vercel Postgres) before production.

## Cloud Agent environment

`.cursor/environment.json` configures the Cursor Cloud Agent environment: `npm ci` on
install and `npm run dev` in a persistent terminal on port 3000.
