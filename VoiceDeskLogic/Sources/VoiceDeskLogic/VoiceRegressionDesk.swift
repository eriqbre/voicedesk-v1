import Foundation

/// Synthetic inbox for voice-regression replay. Not live mail. Not Bridget/Eriq PII.
public enum VoiceRegressionDesk: Sendable {
    public static let murray = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        providerID: "fixture-murray",
        fromName: "Murray Mitchell",
        fromEmail: "murray@example.com",
        sentAtLabel: "Today 9:00 AM",
        subject: "Closing / notarization",
        preview: "Need you to notarize",
        body: "Need you to notarize the closing package today.",
        filterTag: "Inbox"
    )

    public static let murrayOlder = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!,
        providerID: "fixture-murray-old",
        fromName: "Murray Mitchell",
        fromEmail: "murray@example.com",
        sentAtLabel: "Yesterday 4:00 PM",
        subject: "Old walk-through",
        preview: "Can we walk the lot next week?",
        body: "Can we walk the lot next week?",
        filterTag: "Inbox"
    )

    public static let murrayNewest = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000006")!,
        providerID: "fixture-murray-new",
        fromName: "Murray Mitchell",
        fromEmail: "murray@example.com",
        sentAtLabel: "Today 2:00 PM",
        subject: "Walk-through today",
        preview: "Buyer is at the lot now — can you meet?",
        body: "Buyer is at the lot now — can you meet?",
        filterTag: "Inbox"
    )

    /// Multi-match Murray cards after “I found a few matches. Which one?”
    public static var murraySeveralMatches: [EmailItem] {
        [murrayOlder, murray, murrayNewest]
    }

    public static let steve = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
        providerID: "fixture-steve",
        fromName: "Steve Brown",
        fromEmail: "steve@example.com",
        sentAtLabel: "Today 8:00 AM",
        subject: "Inspection note",
        preview: "Punch list is attached.",
        body: "Punch list is attached.",
        filterTag: "Inbox"
    )

    public static let greenacre = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
        providerID: "fixture-greenacre",
        fromName: "Greenacre Properties, Inc.",
        fromEmail: "board@greenacre.example.com",
        sentAtLabel: "Today 10:00 AM",
        subject: "Board meeting notice",
        preview: "Quarterly board meeting is Thursday.",
        body: "The quarterly board meeting is Thursday at 2pm.",
        filterTag: "Inbox"
    )

    public static let laren = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!,
        providerID: "fixture-laren",
        fromName: "Laren Cole",
        fromEmail: "laren@example.com",
        sentAtLabel: "Today 7:30 AM",
        subject: "Walk-through window",
        preview: "Can we do Thursday at 11?",
        body: "Can we do the walk-through Thursday at 11?",
        filterTag: "Inbox"
    )

    public static var snapshot: DeskSnapshot {
        DeskSnapshot(accountEmail: "agent@example.com", emails: [murray, steve])
    }

    /// Dogfood shape: latest inbox is Greenacre, Murray and Laren are further down.
    public static var greenacreFirstSnapshot: DeskSnapshot {
        DeskSnapshot(accountEmail: "agent@example.com", emails: [greenacre, murray, steve, laren])
    }

    public static var greenacreOnlySnapshot: DeskSnapshot {
        DeskSnapshot(accountEmail: "agent@example.com", emails: [greenacre])
    }

    public static var murraySeveralSnapshot: DeskSnapshot {
        DeskSnapshot(accountEmail: "agent@example.com", emails: murraySeveralMatches)
    }

    public static var connected: DeskContext {
        DeskContext(isConnected: true, snapshot: snapshot)
    }

    public static var greenacreFirst: DeskContext {
        DeskContext(isConnected: true, snapshot: greenacreFirstSnapshot)
    }

    public static var greenacreOnly: DeskContext {
        DeskContext(isConnected: true, snapshot: greenacreOnlySnapshot)
    }

    public static func sticky(named raw: String?) -> EmailItem? {
        let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "", "murray", "murray mitchell":
            return murray
        case "steve", "steve brown":
            return steve
        case "greenacre", "greenacre properties, inc.", "greenacre properties":
            return greenacre
        case "laren", "lauren", "laren cole", "lauren cole":
            return laren
        default:
            return nil
        }
    }

    public static func desk(preset raw: String?) -> DeskContext {
        switch (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "greenacre-first":
            return greenacreFirst
        case "greenacre-only":
            return greenacreOnly
        case "murray-several":
            return DeskContext(isConnected: true, snapshot: murraySeveralSnapshot)
        default:
            return connected
        }
    }
}
