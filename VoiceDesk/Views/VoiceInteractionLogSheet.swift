#if DEBUG
import SwiftUI
import UIKit
import VoiceDeskLogic

/// Dogfood-only. Does not exist in Release.
struct VoiceInteractionLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [VoiceInteractionEntry] = VoiceInteractionLog.snapshot()

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("No turns logged yet. Talk or type, then come back.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.intent)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                        Text(entry.userTranscript)
                            .font(.body.weight(.semibold))
                        if !entry.assistantReply.isEmpty {
                            Text(entry.assistantReply)
                                .font(.subheadline)
                        }
                        Text("\(entry.source) · \(entry.voicePath)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !entry.routingNotes.isEmpty {
                            Text(entry.routingNotes.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !entry.cardsAttached.isEmpty {
                            Text(entry.cardsAttached.joined(separator: ", "))
                                .font(.caption2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Voice log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink("Share", item: VoiceInteractionLog.exportJSON())
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Copy all") {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = VoiceInteractionLog.exportJSON()
                        #endif
                    }
                }
            }
            .onAppear {
                entries = VoiceInteractionLog.snapshot()
            }
        }
    }
}
#endif
