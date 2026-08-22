import Foundation

/// Binds a statute confidence percent to the UI tone + citation rule.
public struct ConfidencePresentation: Hashable, Sendable {
    public let percent: Int
    public let band: ConfidenceBand
    public let citation: String

    public init(percent: Int, citation: String = "") {
        self.percent = min(100, max(0, percent))
        self.band = ConfidenceBand.band(for: self.percent)
        self.citation = citation
    }

    public init(statute: StatuteItem) {
        self.init(percent: statute.confidence, citation: statute.citation)
    }

    public var tone: String { band.label }

    /// High-confidence answers must show a source (PRD §6).
    public var requiresCitation: Bool { band == .firm }

    public var citationVisible: Bool {
        requiresCitation && !citation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
