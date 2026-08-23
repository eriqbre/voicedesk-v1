#if DEBUG
import SwiftUI
import VoiceDeskLogic

/// Dogfood-only. Does not exist in Release.
/// The product is the auto-written JSONL path — not Copy / Share / paste.
struct VoiceInteractionLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [VoiceInteractionEntry] = VoiceInteractionLog.snapshot()
    @State private var writtenPaths: [String] = DebugVoiceLogFile.lastWrittenPaths

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Agents read this file automatically. No paste.")
                        .font(.subheadline)
                    Text(VoiceDebugLogPaths.documentedMacPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text("Simulator writes that path on each turn. Device: Files → VoiceDesk-debug, or Save to Files → iCloud Drive / VoiceDesk-debug.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !writtenPaths.isEmpty {
                        ForEach(writtenPaths, id: \.self) { path in
                            Text(path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    Button("Open log folder") {
                        DebugVoiceLogFile.revealInFiles()
                    }
                    .accessibilityIdentifier("debug.voice.log.open-folder")
                    ShareLink("Save to Files", item: DebugVoiceLogFile.documentsFileURL)
                        .accessibilityIdentifier("debug.voice.log.save-files")
                } header: {
                    Text("Auto log")
                } footer: {
                    Text("DEBUG only. Release compiles this out. Never uploaded. `voice-log.jsonl` is gitignored.")
                }

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
            }
            .onAppear {
                DebugVoiceLogFile.ensurePlaceholderFiles()
                entries = VoiceInteractionLog.snapshot()
                writtenPaths = DebugVoiceLogFile.lastWrittenPaths
            }
        }
    }
}
#endif
