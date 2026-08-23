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

    public static var snapshot: DeskSnapshot {
        DeskSnapshot(accountEmail: "agent@example.com", emails: [murray, steve])
    }

    public static var connected: DeskContext {
        DeskContext(isConnected: true, snapshot: snapshot)
    }

    public static func sticky(named raw: String?) -> EmailItem? {
        let key = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "", "murray", "murray mitchell":
            return murray
        case "steve", "steve brown":
            return steve
        default:
            return nil
        }
    }
}
