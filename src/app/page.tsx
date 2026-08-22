import VoiceDesk from "@/components/VoiceDesk";
import { listTickets } from "@/lib/tickets";

export const dynamic = "force-dynamic";

export default function Home() {
  const initialTickets = listTickets();
  return (
    <main className="min-h-screen">
      <VoiceDesk initialTickets={initialTickets} />
    </main>
  );
}
