import { NextResponse } from "next/server";
import { updateTicketStatus, type TicketStatus } from "@/lib/tickets";

const VALID: TicketStatus[] = ["open", "in_progress", "resolved"];

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const { status } = (body ?? {}) as { status?: TicketStatus };

  if (!status || !VALID.includes(status)) {
    return NextResponse.json(
      { error: `status must be one of: ${VALID.join(", ")}` },
      { status: 422 },
    );
  }

  const ticket = updateTicketStatus(id, status);
  if (!ticket) {
    return NextResponse.json({ error: "Ticket not found" }, { status: 404 });
  }

  return NextResponse.json({ ticket });
}
