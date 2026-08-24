import Foundation

/// Immediate desk-email speak after the body is available.
///
/// firstAudio is heuristic-only. Cloud polish (`xaiSummarize`) must not gate
/// `speakDeskReply` — kick it after speak, and never speak the full digest twice.
public struct DeskEmailSpeakPlan: Equatable, Sendable {
    public static let gmailFetchStage = "gmailFetch"
    public static let heuristicStage = "heuristic"
    public static let xaiSummarizeStage = "xaiSummarize"

    public var spokenText: String
    public var stagesBeforeFirstAudio: [String]
    public var voiceLogNotes: [String]

    public init(spokenText: String, stagesBeforeFirstAudio: [String], voiceLogNotes: [String]) {
        self.spokenText = spokenText
        self.stagesBeforeFirstAudio = stagesBeforeFirstAudio
        self.voiceLogNotes = voiceLogNotes
    }

    public static func afterBodyAvailable(
        _ request: EmailSummaryRequest,
        didFetchBody: Bool = true
    ) -> DeskEmailSpeakPlan {
        var stages: [String] = []
        if didFetchBody {
            stages.append(gmailFetchStage)
        }
        stages.append(heuristicStage)
        return DeskEmailSpeakPlan(
            spokenText: EmailSummary.heuristic(request),
            stagesBeforeFirstAudio: stages,
            voiceLogNotes: [
                "firstAudio: \(stages.joined(separator: "+"))",
                "firstAudio skipped xaiSummarize",
                "xaiSummarize: async unused for speak"
            ]
        )
    }

    public static func firstAudioWaitsOnXAISummarize(_ stages: [String]) -> Bool {
        stages.contains(xaiSummarizeStage)
    }

    /// Quiet thread-text upgrade only. Never a second spoken digest.
    public static func cardTextUpgrade(spoken: String, polished: String) -> String? {
        let cleaned = EmailSummary.scrubUIChrome(polished)
        guard !cleaned.isEmpty, !EmailSummary.containsUIChrome(cleaned) else {
            return nil
        }
        guard cleaned != spoken else {
            return nil
        }
        return cleaned
    }
}
