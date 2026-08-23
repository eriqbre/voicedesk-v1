import SwiftUI
import VoiceDeskLogic

/// Dogfood-only. Hidden on App Store production (`VoiceDogfoodGate`).
/// The product is the auto-written JSONL / cloud gist — not Copy / Share / paste.
struct VoiceInteractionLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [VoiceInteractionEntry] = VoiceInteractionLog.snapshot()
    #if DEBUG
    @State private var writtenPaths: [String] = DebugVoiceLogFile.lastWrittenPaths
    #endif
    @Bindable private var cloud = VoiceCloudDogfoodSettings.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Cloud dogfood log", isOn: $cloud.isEnabled)
                        .accessibilityIdentifier("debug.voice.cloud.toggle")
                    Text(cloud.isEnabled
                         ? "On by default. Every turn uploads automatically. Flip off to stop."
                         : "Off. DEBUG / TestFlight only. App Store production never uploads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(cloud.isEnabled ? "debug.voice.cloud.on" : "debug.voice.cloud.off")
                    if cloud.showsMissingTokenBanner {
                        Text("Add VOICE_DOGFOOD_GITHUB_TOKEN to Secrets.plist once")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !cloud.lastDestination.isEmpty {
                        Text(cloud.lastDestination)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    } else if let destination = cloud.config?.pullHint {
                        Text(destination)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    if !cloud.lastStatus.isEmpty {
                        Text(cloud.lastStatus)
                            .font(.caption)
                    }
                    if !cloud.lastError.isEmpty {
                        Text(cloud.lastError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Cloud dogfood log")
                } footer: {
                    Text("Elon pulls the gist by description using the Secrets token. No gist id, no paste.")
                }

                #if DEBUG
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
                    Text("Mac / Files log")
                } footer: {
                    Text("DEBUG only. `voice-log.jsonl` is gitignored. Cloud upload is separate and opt-in.")
                }
                #endif

                if entries.isEmpty {
                    Text("No turns logged yet. Talk or type, then come back.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.intent)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.accent)
                            if entry.sticky != .none {
                                Text(entry.sticky.rawValue)
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                        Text(entry.userTranscript)
                            .font(.body.weight(.semibold))
                        if let person = entry.focusedPerson, !person.isEmpty {
                            Text("focusedPerson \(person)")
                                .font(.caption)
                        }
                        if let query = entry.searchQuery, !query.isEmpty {
                            Text("q=\(query)")
                                .font(.caption.monospaced())
                        }
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
                        if !entry.errors.isEmpty {
                            Text(entry.errors.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.red)
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
                #if DEBUG
                DebugVoiceLogFile.ensurePlaceholderFiles()
                writtenPaths = DebugVoiceLogFile.lastWrittenPaths
                #endif
                entries = VoiceInteractionLog.snapshot()
            }
        }
    }
}

struct CloudDogfoodMissingTokenBanner: View {
    var body: some View {
        Text("Add VOICE_DOGFOOD_GITHUB_TOKEN to Secrets.plist once")
            .font(.caption)
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accentSoft)
            .accessibilityIdentifier("debug.voice.cloud.missing-token")
            .accessibilityLabel("Add VOICE_DOGFOOD_GITHUB_TOKEN to Secrets.plist once")
    }
}
