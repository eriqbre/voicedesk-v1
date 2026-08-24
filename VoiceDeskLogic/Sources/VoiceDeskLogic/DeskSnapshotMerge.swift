import Foundation

/// Hot-cache merge. The inbox pull is a window; the snapshot is the store.
///
/// Sync never drops an `EmailItem` we already have (same `providerID` / `id`).
/// New inbox IDs insert. Existing rows update in place (keep local `id` and
/// any richer body already fetched). Offline / error paths keep the last store.
public enum DeskSnapshotMerge: Sendable {
    public static func applying(incoming: DeskSnapshot, onto cached: DeskSnapshot) -> DeskSnapshot {
        DeskSnapshot(
            accountEmail: incoming.accountEmail ?? cached.accountEmail,
            lastSyncedAt: incoming.lastSyncedAt ?? cached.lastSyncedAt,
            emails: emails(incoming: incoming.emails, onto: cached.emails),
            events: incoming.events,
            tasks: incoming.tasks,
            lastError: incoming.lastError
        )
    }

    public static func emails(incoming: [EmailItem], onto cached: [EmailItem]) -> [EmailItem] {
        var indexByKey: [String: Int] = [:]
        for (offset, email) in cached.enumerated() {
            for key in identityKeys(email) where indexByKey[key] == nil {
                indexByKey[key] = offset
            }
        }

        var seenCached = Set<Int>()
        var result: [EmailItem] = []

        for item in incoming {
            if let cachedIndex = cachedIndex(for: item, indexByKey: indexByKey),
               !seenCached.contains(cachedIndex) {
                seenCached.insert(cachedIndex)
                result.append(updated(cached[cachedIndex], with: item))
            } else {
                result.append(item)
            }
        }

        for (offset, email) in cached.enumerated() where !seenCached.contains(offset) {
            result.append(email)
        }
        return result
    }

    /// Keys that identify one cached row. Prefer Gmail `providerID`, then local `id`.
    public static func identityKeys(_ email: EmailItem) -> [String] {
        var keys: [String] = []
        if let providerID = email.providerID, !providerID.isEmpty {
            keys.append("p:\(providerID)")
        }
        keys.append("id:\(email.id.uuidString)")
        return keys
    }

    public static func updated(_ existing: EmailItem, with incoming: EmailItem) -> EmailItem {
        EmailItem(
            id: existing.id,
            providerID: firstNonEmpty(incoming.providerID, existing.providerID),
            threadID: firstNonEmpty(incoming.threadID, existing.threadID),
            fromName: incoming.fromName.isEmpty ? existing.fromName : incoming.fromName,
            fromEmail: incoming.fromEmail.isEmpty ? existing.fromEmail : incoming.fromEmail,
            sentAtLabel: incoming.sentAtLabel.isEmpty ? existing.sentAtLabel : incoming.sentAtLabel,
            subject: incoming.subject.isEmpty ? existing.subject : incoming.subject,
            preview: incoming.preview.isEmpty ? existing.preview : incoming.preview,
            body: richer(incoming.body, existing.body),
            htmlBody: richer(incoming.htmlBody, existing.htmlBody),
            earlierMessages: incoming.earlierMessages.isEmpty
                ? existing.earlierMessages
                : incoming.earlierMessages,
            filterTag: incoming.filterTag.isEmpty ? existing.filterTag : incoming.filterTag,
            relatedListing: incoming.relatedListing ?? existing.relatedListing,
            relatedPeople: incoming.relatedPeople.isEmpty ? existing.relatedPeople : incoming.relatedPeople,
            cardPresentation: incoming.cardPresentation
        )
    }

    private static func cachedIndex(
        for email: EmailItem,
        indexByKey: [String: Int]
    ) -> Int? {
        for key in identityKeys(email) {
            if let index = indexByKey[key] {
                return index
            }
        }
        return nil
    }

    private static func firstNonEmpty(_ incoming: String?, _ existing: String?) -> String? {
        if let incoming, !incoming.isEmpty { return incoming }
        if let existing, !existing.isEmpty { return existing }
        return incoming ?? existing
    }

    private static func richer(_ incoming: String?, _ existing: String?) -> String? {
        let next = incoming?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !next.isEmpty { return incoming }
        let kept = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return kept.isEmpty ? incoming : existing
    }
}
