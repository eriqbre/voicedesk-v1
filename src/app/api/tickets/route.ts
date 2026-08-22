import { NextResponse } from "next/server";
import { createTicket, listTickets } from "@/lib/tickets";

export async function GET() {
  return NextResponse.json({ tickets: listTickets() });
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { transcript, channel } = (body ?? {}) as {
    transcript?: string;
    channel?: "voice" | "text";
  };

  if (typeof transcript !== "string" || transcript.trim().length === 0) {
    return NextResponse.json(
      { error: "A non-empty transcript is required" },
      { status: 422 },
    );
  }

  const ticket = createTicket({ transcript, channel });
  return NextResponse.json({ ticket }, { status: 201 });
}
