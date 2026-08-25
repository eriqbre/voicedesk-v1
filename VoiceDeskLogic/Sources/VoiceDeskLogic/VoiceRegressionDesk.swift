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

    /// Joint “Alex & Laren” — newer than Laren Jansen. Must not win a Lauren ask silently.
    public static let alexAndLaren = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000007")!,
        providerID: "fixture-alex-laren",
        fromName: "Alex & Laren",
        fromEmail: "alex.laren@example.com",
        sentAtLabel: "Today 3:00 PM",
        subject: "Family Fun Day",
        preview: "Picnic this Saturday?",
        body: "Picnic this Saturday at the park.",
        filterTag: "Inbox"
    )

    public static let larenJansen = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000008")!,
        providerID: "fixture-laren-jansen",
        fromName: "Laren Jansen",
        fromEmail: "laren.jansen@example.com",
        sentAtLabel: "Today 11:00 AM",
        subject: "Fleeman Road disclosures",
        preview: "Disclosures for Fleeman Road are attached.",
        body: "Disclosures for the Fleeman Road listing are attached.",
        filterTag: "Inbox"
    )

    /// Dogfood 2026-08-25 walk: Murray Mitchell / 302 Georgia Ave closing.
    /// Subject + first useful line only — do not invent a closing plot.
    public static let murrayGeorgia = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!,
        providerID: "fixture-murray-georgia",
        fromName: "Murray Mitchell",
        fromEmail: "murray@example.com",
        sentAtLabel: "Today 3:30 PM",
        subject: "Re: 302 GEORGIA AVE, Crystal Beach, FL 34681/CLOSING INFORMATION REQUIRED",
        preview: "CLOSING INFORMATION REQUIRED",
        body: "CLOSING INFORMATION REQUIRED for 302 GEORGIA AVE, Crystal Beach, FL 34681.",
        filterTag: "Inbox"
    )

    /// Dogfood 2026-08-24 empty-mouth: Sandy Woodcock / “My gut tells me”.
    public static let sandyGut = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-00000000000C")!,
        providerID: "fixture-sandy-gut",
        fromName: "Sandy Woodcock",
        fromEmail: "sandy@example.com",
        sentAtLabel: "Today 2:15 PM",
        subject: "My gut tells me",
        preview: "My gut tells me",
        body: "My gut tells me",
        filterTag: "Inbox"
    )

    public static let ericGross = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000009")!,
        providerID: "fixture-eric-gross",
        fromName: "Eric Gross",
        fromEmail: "eric.gross@example.com",
        sentAtLabel: "Today 1:00 PM",
        subject: "Offer update",
        preview: "Buyer is ready to sign.",
        body: "Buyer is ready to sign the offer.",
        filterTag: "Inbox"
    )

    /// Mailbox-owner self mail. Eric must not silently become this Eriq.
    public static let eriqSelf = EmailItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!,
        providerID: "fixture-eriq-self",
        fromName: "Eriq Cole",
        fromEmail: "eriq@example.com",
        sentAtLabel: "Today 4:00 PM",
        subject: "Re: listing notes",
        preview: "Sending myself the punch list.",
        body: "Sending myself the punch list.",
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

    /// Alex & Laren is newer; Laren Jansen has Fleeman. Distinct people.
    public static var laurenSeveralSnapshot: DeskSnapshot {
        DeskSnapshot(accountEmail: "agent@example.com", emails: [alexAndLaren, larenJansen, greenacre])
    }

    public static var ericWithGrossSnapshot: DeskSnapshot {
        DeskSnapshot(accountEmail: "eriq@example.com", emails: [eriqSelf, ericGross])
    }

    public static var ericSelfOnlySnapshot: DeskSnapshot {
        DeskSnapshot(accountEmail: "eriq@example.com", emails: [eriqSelf])
    }

    /// Murray 302 + Sandy gut — leftover-stem / empty-speak walk fixtures.
    public static var leftoverSpeakSnapshot: DeskSnapshot {
        DeskSnapshot(accountEmail: "agent@example.com", emails: [murrayGeorgia, sandyGut])
    }

    public static var leftoverSpeak: DeskContext {
        DeskContext(isConnected: true, snapshot: leftoverSpeakSnapshot)
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

    public static var laurenSeveral: DeskContext {
        DeskContext(isConnected: true, snapshot: laurenSeveralSnapshot)
    }

    public static var ericWithGross: DeskContext {
        DeskContext(
            isConnected: true,
            snapshot: ericWithGrossSnapshot,
            auth: GoogleAuthSnapshot.reduce(.signedOut, .connectSucceeded(email: "eriq@example.com"))
        )
    }

    public static var ericSelfOnly: DeskContext {
        DeskContext(
            isConnected: true,
            snapshot: ericSelfOnlySnapshot,
            auth: GoogleAuthSnapshot.reduce(.signedOut, .connectSucceeded(email: "eriq@example.com"))
        )
    }

    public static func sticky(named raw: String?) -> EmailItem? {
        let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "", "murray", "murray mitchell":
            return murray
        case "murray georgia", "302 georgia":
            return murrayGeorgia
        case "sandy", "sandy woodcock":
            return sandyGut
        case "steve", "steve brown":
            return steve
        case "greenacre", "greenacre properties, inc.", "greenacre properties":
            return greenacre
        case "laren", "lauren", "laren cole", "lauren cole":
            return laren
        case "alex", "alex & laren", "alex and laren":
            return alexAndLaren
        case "laren jansen", "jansen":
            return larenJansen
        case "eric", "eric gross":
            return ericGross
        case "eriq", "eriq cole":
            return eriqSelf
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
        case "lauren-several":
            return laurenSeveral
        case "eric-with-gross":
            return ericWithGross
        case "eric-self-only":
            return ericSelfOnly
        case "leftover-speak":
            return leftoverSpeak
        default:
            return connected
        }
    }
}
