export type TicketStatus = "open" | "in_progress" | "resolved";
export type TicketPriority = "low" | "medium" | "high";

export interface Ticket {
  id: string;
  subject: string;
  transcript: string;
  channel: "voice" | "text";
  status: TicketStatus;
  priority: TicketPriority;
  createdAt: string;
}

export interface CreateTicketInput {
  transcript: string;
  channel?: "voice" | "text";
}

// In-memory store. Persists for the lifetime of the server process, which is
// sufficient for local development and environment validation. Swap for a real
// database (e.g. Vercel Postgres) before production use.
const store: { tickets: Ticket[] } = globalThis.__voicedeskStore ?? {
  tickets: seed(),
};

if (process.env.NODE_ENV !== "production") {
  globalThis.__voicedeskStore = store;
}

function seed(): Ticket[] {
  return [
    {
      id: "TCK-1001",
      subject: "Cannot reset my account password",
      transcript:
        "Hi, I've been trying to reset my password for the last hour but the reset email never arrives. Can someone help me get back into my account?",
      channel: "voice",
      status: "open",
      priority: "high",
      createdAt: new Date(Date.now() - 1000 * 60 * 42).toISOString(),
    },
    {
      id: "TCK-1000",
      subject: "Question about upgrading my plan",
      transcript:
        "I'd like to understand the difference between the Pro and Team plans before I upgrade my subscription.",
      channel: "text",
      status: "resolved",
      priority: "low",
      createdAt: new Date(Date.now() - 1000 * 60 * 60 * 5).toISOString(),
    },
  ];
}

const HIGH_SIGNAL = ["urgent", "asap", "immediately", "can't", "cannot", "broken", "down", "error", "fail", "charged", "refund"];
const LOW_SIGNAL = ["question", "wondering", "curious", "how do", "when", "info"];

function derivePriority(text: string): TicketPriority {
  const lower = text.toLowerCase();
  if (HIGH_SIGNAL.some((w) => lower.includes(w))) return "high";
  if (LOW_SIGNAL.some((w) => lower.includes(w))) return "low";
  return "medium";
}

function deriveSubject(text: string): string {
  const cleaned = text.trim().replace(/\s+/g, " ");
  if (!cleaned) return "New support request";
  const firstSentence = cleaned.split(/[.!?\n]/)[0].trim();
  const base = firstSentence.length > 4 ? firstSentence : cleaned;
  return base.length > 72 ? `${base.slice(0, 69)}...` : base;
}

let counter = 1002;

export function listTickets(): Ticket[] {
  return [...store.tickets].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export function createTicket(input: CreateTicketInput): Ticket {
  const transcript = (input.transcript ?? "").trim();
  if (!transcript) {
    throw new Error("transcript is required");
  }
  const ticket: Ticket = {
    id: `TCK-${counter++}`,
    subject: deriveSubject(transcript),
    transcript,
    channel: input.channel === "voice" ? "voice" : "text",
    status: "open",
    priority: derivePriority(transcript),
    createdAt: new Date().toISOString(),
  };
  store.tickets.push(ticket);
  return ticket;
}

export function updateTicketStatus(id: string, status: TicketStatus): Ticket | null {
  const ticket = store.tickets.find((t) => t.id === id);
  if (!ticket) return null;
  ticket.status = status;
  return ticket;
}

declare global {
  var __voicedeskStore: { tickets: Ticket[] } | undefined;
}
