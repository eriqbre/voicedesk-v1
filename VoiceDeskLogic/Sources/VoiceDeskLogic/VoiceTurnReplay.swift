import Foundation

/// Offline replay of one voice turn. No network. Used by CI fixtures and dogfood promotion.
public enum VoiceTurnReplay: Sendable {
    public struct Result: Equatable, Sendable {
        public var intent: String
        public var notes: [String]
        public var ownsDeskTurn: Bool
        public var looksLikeMailAsk: Bool
        public var evidence: ConversationPresence.DeskEvidence?
        public var cardLabels: [String]
        public var gmailQuery: String?
        public var shouldSearchGmail: Bool
        public var stickyCleared: Bool
        public var reply: String

        public var attachesEmailCard: Bool {
            cardLabels.contains { $0.hasPrefix("email:") }
        }

        public var attachesCalendarCard: Bool {
            cardLabels.contains { $0.hasPrefix("calendar:") }
        }

        /// Chat-bubble copy. Cards-only turns (inbox glance, calendar overview) are empty.
        public var onScreen: String {
            guard let evidence else { return reply }
            return InboxGlance.onScreenText(for: evidence)
        }

        public init(
            intent: String,
            notes: [String],
            ownsDeskTurn: Bool,
            looksLikeMailAsk: Bool,
            evidence: ConversationPresence.DeskEvidence?,
            cardLabels: [String],
            gmailQuery: String?,
            shouldSearchGmail: Bool,
            stickyCleared: Bool,
            reply: String
        ) {
            self.intent = intent
            self.notes = notes
            self.ownsDeskTurn = ownsDeskTurn
            self.looksLikeMailAsk = looksLikeMailAsk
            self.evidence = evidence
            self.cardLabels = cardLabels
            self.gmailQuery = gmailQuery
            self.shouldSearchGmail = shouldSearchGmail
            self.stickyCleared = stickyCleared
            self.reply = reply
        }
    }

    public static func play(
        utterance: String,
        context: DeskContext,
        focusedEmail: EmailItem? = nil,
        pendingSearchClarify: Bool = false,
        clarifyMatches: [EmailItem] = [],
        pendingSenderRefine: Bool = false,
        priorSearchAsk: String? = nil
    ) -> Result {
        let cleaned = EarlyFinalHold.dropLeadingLeftoverStem(utterance)
        let evidence = ConversationPresence.deskEvidence(
            for: cleaned,
            context: context,
            focusedEmail: focusedEmail,
            pendingSearchClarify: pendingSearchClarify,
            clarifyMatches: clarifyMatches,
            pendingSenderRefine: pendingSenderRefine,
            priorSearchAsk: priorSearchAsk
        )
        let classified = VoiceInteractionLog.classify(
            utterance: cleaned,
            evidence: evidence,
            pendingSearchClarify: pendingSearchClarify,
            hadFocusedEmail: focusedEmail != nil,
            hasClarifyMatches: !clarifyMatches.isEmpty,
            pendingSenderRefine: pendingSenderRefine
        )
        return Result(
            intent: classified.intent,
            notes: classified.notes,
            ownsDeskTurn: ConversationPresence.ownsConnectedDeskTurn(
                cleaned,
                pendingSearchClarify: pendingSearchClarify,
                hasClarifyMatches: !clarifyMatches.isEmpty,
                hasFocusedEmail: focusedEmail != nil,
                pendingSenderRefine: pendingSenderRefine,
                events: context.snapshot.events
            ),
            looksLikeMailAsk: ConversationPresence.looksLikeMailAsk(cleaned),
            evidence: evidence,
            cardLabels: VoiceInteractionLog.cardLabels(evidence?.cards ?? []),
            gmailQuery: evidence?.gmailQuery,
            shouldSearchGmail: evidence?.shouldSearchGmail ?? false,
            stickyCleared: evidence?.resetsFocusedEmail == true,
            reply: spokenReply(evidence: evidence)
        )
    }

    private static func spokenReply(evidence: ConversationPresence.DeskEvidence?) -> String {
        guard let evidence else { return "" }
        // List/show is empty — cards are the list. Do not fill
        // spokenDeskHit when the leftover ack is gone.
        if evidence.shouldGlanceInbox || evidence.topic == .calendar {
            return evidence.text
        }
        if let email = evidence.focusedEmail
            ?? evidence.cards.compactMap({ card -> EmailItem? in
                if case .email(let item) = card { return item }
                return nil
            }).first,
           VoiceInteractionLog.cardLabels(evidence.cards).contains(where: { $0.hasPrefix("email:") }) {
            if DeskReplySpeech.textToSpeak(evidence.text, lastSpoken: nil) != nil {
                return evidence.text
            }
            return DeskReplySpeech.spokenDeskHit(
                email,
                includeEarlier: evidence.expandEarlierMessages
            )
        }
        return evidence.text
    }

    public static func play(_ fixture: VoiceRegressionFixture, desk: DeskContext? = nil) -> Result {
        let context: DeskContext
        if let desk {
            context = desk
        } else if fixture.connected == false {
            context = .disconnected
        } else {
            context = VoiceRegressionDesk.desk(preset: fixture.deskPreset)
        }
        let focused: EmailItem?
        if fixture.hadFocusedEmail == true {
            focused = VoiceRegressionDesk.sticky(named: fixture.stickyFromName) ?? VoiceRegressionDesk.murray
        } else {
            focused = nil
        }
        let pendingClarify = fixture.pendingSearchClarify ?? false
        let pendingRefine = fixture.pendingSenderRefine ?? false
        // After “I found a few matches. Which one?” replay the compact cards as clarify matches
        // so “the last one” / “the latest” pick newest Murray — not live Grok.
        let matches = pendingClarify ? context.snapshot.emails : []
        return play(
            utterance: fixture.userTranscript,
            context: context,
            focusedEmail: focused,
            pendingSearchClarify: pendingClarify,
            clarifyMatches: matches,
            pendingSenderRefine: pendingRefine,
            priorSearchAsk: fixture.priorSearchAsk
        )
    }
}
