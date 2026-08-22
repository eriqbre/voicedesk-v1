"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useSpeechRecognition } from "@/hooks/useSpeechRecognition";
import type { Ticket, TicketStatus } from "@/lib/tickets";

const STATUS_LABEL: Record<TicketStatus, string> = {
  open: "Open",
  in_progress: "In progress",
  resolved: "Resolved",
};

const STATUS_STYLE: Record<TicketStatus, string> = {
  open: "bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-300",
  in_progress: "bg-sky-100 text-sky-800 dark:bg-sky-500/15 dark:text-sky-300",
  resolved: "bg-emerald-100 text-emerald-800 dark:bg-emerald-500/15 dark:text-emerald-300",
};

const PRIORITY_STYLE: Record<string, string> = {
  high: "text-rose-600 dark:text-rose-400",
  medium: "text-amber-600 dark:text-amber-400",
  low: "text-slate-500 dark:text-slate-400",
};

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.round(diff / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

export default function VoiceDesk({ initialTickets }: { initialTickets: Ticket[] }) {
  const [tickets, setTickets] = useState<Ticket[]>(initialTickets);
  const [draft, setDraft] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [usedVoice, setUsedVoice] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  const speech = useSpeechRecognition();

  // While listening, show the live transcript; otherwise show the editable draft.
  const displayValue = speech.listening ? speech.transcript : draft;

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3000);
    return () => clearTimeout(t);
  }, [toast]);

  const stats = useMemo(() => {
    return {
      total: tickets.length,
      open: tickets.filter((t) => t.status !== "resolved").length,
      resolved: tickets.filter((t) => t.status === "resolved").length,
    };
  }, [tickets]);

  const toggleMic = useCallback(() => {
    if (speech.listening) {
      speech.stop();
      // Commit whatever was transcribed into the editable draft.
      setDraft(speech.transcript);
      setUsedVoice(true);
    } else {
      speech.reset();
      setDraft("");
      setUsedVoice(false);
      speech.start();
    }
  }, [speech]);

  const submit = useCallback(async () => {
    const transcript = (speech.listening ? speech.transcript : draft).trim();
    if (!transcript || submitting) return;
    if (speech.listening) speech.stop();
    setSubmitting(true);
    try {
      const res = await fetch("/api/tickets", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          transcript,
          channel: usedVoice || speech.listening ? "voice" : "text",
        }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data.error ?? "Failed to create ticket");
      }
      const { ticket } = (await res.json()) as { ticket: Ticket };
      setTickets((prev) => [ticket, ...prev]);
      setDraft("");
      setUsedVoice(false);
      speech.reset();
      setToast(`Created ${ticket.id} · priority ${ticket.priority}`);
    } catch (err) {
      setToast(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setSubmitting(false);
    }
  }, [draft, submitting, usedVoice, speech]);

  const changeStatus = useCallback(async (id: string, status: TicketStatus) => {
    const previous = tickets;
    setTickets((prev) => prev.map((t) => (t.id === id ? { ...t, status } : t)));
    try {
      const res = await fetch(`/api/tickets/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status }),
      });
      if (!res.ok) throw new Error("update failed");
    } catch {
      setTickets(previous);
      setToast("Could not update ticket status");
    }
  }, [tickets]);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
      <header className="mb-8 flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-indigo-500 to-violet-600 text-white shadow-lg shadow-indigo-500/30">
            <MicIcon className="h-6 w-6" />
          </div>
          <div>
            <h1 className="text-xl font-semibold tracking-tight">VoiceDesk</h1>
            <p className="text-sm text-slate-500 dark:text-slate-400">
              Voice-first help desk
            </p>
          </div>
        </div>
        <div className="flex gap-6">
          <Stat label="Total" value={stats.total} />
          <Stat label="Active" value={stats.open} accent="text-amber-600 dark:text-amber-400" />
          <Stat label="Resolved" value={stats.resolved} accent="text-emerald-600 dark:text-emerald-400" />
        </div>
      </header>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]">
        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <h2 className="text-base font-semibold">New support request</h2>
          <p className="mt-1 text-sm text-slate-500 dark:text-slate-400">
            Dictate or type a request. VoiceDesk drafts the ticket and auto-triages priority.
          </p>

          <div className="mt-6 flex flex-col items-center gap-3">
            <button
              type="button"
              onClick={toggleMic}
              disabled={!speech.supported}
              aria-pressed={speech.listening}
              aria-label={speech.listening ? "Stop recording" : "Start recording"}
              className={`relative flex h-24 w-24 items-center justify-center rounded-full transition disabled:cursor-not-allowed disabled:opacity-40 ${
                speech.listening
                  ? "bg-rose-500 text-white shadow-lg shadow-rose-500/40"
                  : "bg-indigo-600 text-white shadow-lg shadow-indigo-600/30 hover:bg-indigo-500"
              }`}
            >
              {speech.listening && (
                <span className="absolute inset-0 animate-ping rounded-full bg-rose-400/60" />
              )}
              <MicIcon className="relative h-9 w-9" />
            </button>
            <span className="text-sm font-medium text-slate-600 dark:text-slate-300">
              {speech.listening ? "Listening… tap to stop" : speech.supported ? "Tap to speak" : "Voice input unavailable"}
            </span>
            {!speech.supported && (
              <span className="text-center text-xs text-slate-400">
                This browser has no Web Speech API. You can still type your request below.
              </span>
            )}
            {speech.error && (
              <span className="text-center text-xs text-rose-500">{speech.error}</span>
            )}
          </div>

          <label htmlFor="transcript" className="mt-6 block text-sm font-medium">
            Transcript
          </label>
          <textarea
            id="transcript"
            value={displayValue}
            readOnly={speech.listening}
            onChange={(e) => {
              setDraft(e.target.value);
              setUsedVoice(false);
            }}
            rows={5}
            placeholder="e.g. I was charged twice this month and need a refund as soon as possible."
            className="mt-2 w-full resize-none rounded-xl border border-slate-200 bg-slate-50 p-3 text-sm outline-none ring-indigo-500 transition focus:ring-2 dark:border-slate-700 dark:bg-slate-950"
          />

          <button
            type="button"
            onClick={submit}
            disabled={!displayValue.trim() || submitting}
            className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-indigo-600 px-4 py-3 text-sm font-semibold text-white transition hover:bg-indigo-500 disabled:cursor-not-allowed disabled:opacity-50"
          >
            {submitting ? "Creating ticket…" : "Create ticket"}
          </button>
        </section>

        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-base font-semibold">Ticket queue</h2>
            <span className="text-xs text-slate-400">{tickets.length} tickets</span>
          </div>
          <ul className="flex flex-col gap-3">
            {tickets.length === 0 && (
              <li className="rounded-xl border border-dashed border-slate-300 p-8 text-center text-sm text-slate-400 dark:border-slate-700">
                No tickets yet. Create one on the left.
              </li>
            )}
            {tickets.map((ticket) => (
              <li
                key={ticket.id}
                className="rounded-xl border border-slate-200 p-4 transition hover:border-indigo-300 dark:border-slate-800"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2 text-xs text-slate-400">
                      <span className="font-mono">{ticket.id}</span>
                      <span aria-hidden>·</span>
                      <span className="inline-flex items-center gap-1">
                        {ticket.channel === "voice" ? <MicIcon className="h-3 w-3" /> : <TextIcon className="h-3 w-3" />}
                        {ticket.channel}
                      </span>
                      <span aria-hidden>·</span>
                      <span>{timeAgo(ticket.createdAt)}</span>
                    </div>
                    <h3 className="mt-1 truncate font-medium">{ticket.subject}</h3>
                    <p className="mt-1 line-clamp-2 text-sm text-slate-500 dark:text-slate-400">
                      {ticket.transcript}
                    </p>
                  </div>
                  <div className="flex flex-col items-end gap-2">
                    <span className={`rounded-full px-2.5 py-1 text-xs font-medium ${STATUS_STYLE[ticket.status]}`}>
                      {STATUS_LABEL[ticket.status]}
                    </span>
                    <span className={`text-xs font-semibold uppercase tracking-wide ${PRIORITY_STYLE[ticket.priority]}`}>
                      {ticket.priority}
                    </span>
                  </div>
                </div>
                <div className="mt-3 flex flex-wrap gap-2">
                  {(["open", "in_progress", "resolved"] as TicketStatus[])
                    .filter((s) => s !== ticket.status)
                    .map((s) => (
                      <button
                        key={s}
                        type="button"
                        onClick={() => changeStatus(ticket.id, s)}
                        className="rounded-lg border border-slate-200 px-2.5 py-1 text-xs font-medium text-slate-600 transition hover:border-indigo-400 hover:text-indigo-600 dark:border-slate-700 dark:text-slate-300"
                      >
                        Mark {STATUS_LABEL[s].toLowerCase()}
                      </button>
                    ))}
                </div>
              </li>
            ))}
          </ul>
        </section>
      </div>

      {toast && (
        <div
          role="status"
          className="fixed bottom-6 left-1/2 -translate-x-1/2 rounded-full bg-slate-900 px-5 py-2.5 text-sm font-medium text-white shadow-lg dark:bg-white dark:text-slate-900"
        >
          {toast}
        </div>
      )}
    </div>
  );
}

function Stat({ label, value, accent }: { label: string; value: number; accent?: string }) {
  return (
    <div className="text-right">
      <div className={`text-2xl font-semibold ${accent ?? ""}`}>{value}</div>
      <div className="text-xs uppercase tracking-wide text-slate-400">{label}</div>
    </div>
  );
}

function MicIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z" />
      <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
      <line x1="12" y1="19" x2="12" y2="22" />
    </svg>
  );
}

function TextIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M4 6h16M4 12h16M4 18h10" />
    </svg>
  );
}
