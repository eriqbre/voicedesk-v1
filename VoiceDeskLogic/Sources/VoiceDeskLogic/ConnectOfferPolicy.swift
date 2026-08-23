import Foundation

/// First-run connect offer vs returning soft prompt. Never a nag wall.
public enum ConnectOfferPolicy: Sendable {
    public static let softPromptCooldown: TimeInterval = 86_400

    public static func shouldShowFirstConnectOffer(
        playbookCompleted: Bool,
        hasSeenOffer: Bool,
        isConnected: Bool
    ) -> Bool {
        playbookCompleted && !hasSeenOffer && !isConnected
    }

    public static func shouldSoftPrompt(
        isConnected: Bool,
        lastSoftPromptAt: Date?,
        now: Date = Date(),
        cooldown: TimeInterval = softPromptCooldown
    ) -> Bool {
        guard !isConnected else { return false }
        guard let lastSoftPromptAt else { return true }
        return now.timeIntervalSince(lastSoftPromptAt) >= cooldown
    }
}
