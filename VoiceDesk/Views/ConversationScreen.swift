import SwiftUI
import VoiceDeskLogic

struct ConversationScreen: View {
    @Environment(AppModel.self) private var model
    @Bindable private var cloudLog = VoiceCloudDogfoodSettings.shared

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    if cloudLog.showsMissingTokenBanner {
                        CloudDogfoodMissingTokenBanner()
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                ForEach(model.turns) { turn in
                                    TurnView(turn: turn)
                                        .id(turn.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { _ in model.noteUserScrolling() }
                        )
                        .onChange(of: model.conversationScrollEpoch) { _, _ in
                            scrollForCurrentIntent(proxy)
                        }
                    }
                    if model.voice.needsCredentials || model.showVoiceSetup {
                        VoiceSetupBanner()
                    }
                    VoiceBar()
                }
            }
            .navigationTitle("VoiceDesk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.google.isConnected {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Disconnect Google") {
                            model.disconnectGoogle()
                        }
                        .accessibilityIdentifier("google.disconnect.toolbar")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.showActivity = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Activity")
                }
                if cloudLog.allowsLogging {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.showVoiceLog = true
                        } label: {
                            Image(systemName: cloudLog.isEnabled ? "ladybug.fill" : "ladybug")
                        }
                        .accessibilityLabel("Voice log")
                        .accessibilityIdentifier("debug.voice.log")
                    }
                }
            }
            .onChange(of: model.voice.state) { _, state in
                model.voiceBecame(state)
            }
            .sheet(isPresented: $model.showActivity) {
                ActivitySheet()
            }
            .sheet(isPresented: $model.showVoiceLog) {
                VoiceInteractionLogSheet()
            }
        }
    }

    private func scrollForCurrentIntent(_ proxy: ScrollViewProxy) {
        guard !model.userOwnsConversationScroll else { return }
        let target = model.conversationScrollTarget ?? model.lastTurnID
        guard let target else { return }
        let unit: UnitPoint = model.conversationScrollAnchor == .center ? .center : .top
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.easeOut(duration: 0.28)) {
                proxy.scrollTo(target, anchor: unit)
            }
        }
    }
}

struct TurnView: View {
    @Environment(AppModel.self) private var model
    let turn: ConversationTurn

    var body: some View {
        VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 10) {
            if !turn.text.isEmpty {
                Text(turn.text)
                    .font(.body)
                    .foregroundStyle(turn.role == .user ? Color.white : Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        turn.role == .user ? Palette.userBubble : Color.white,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay {
                        if turn.role == .assistant {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Palette.line)
                        }
                    }
                    .frame(maxWidth: turn.role == .user ? 320 : .infinity, alignment: turn.role == .user ? .trailing : .leading)
                    .accessibilityLabel(turn.role == .user ? "You: \(turn.text)" : "VoiceDesk: \(turn.text)")
            }

            ForEach(turn.cards) { card in
                ContentCardView(card: card)
                    .id(card.id)
            }

            if !turn.suggestions.isEmpty {
                FlowSuggestions(suggestions: turn.suggestions) { model.useSuggestion($0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
    }
}

struct FlowSuggestions: View {
    let suggestions: [String]
    var onTap: (String) -> Void

    var body: some View {
        FlexibleChipRow(items: suggestions, onTap: onTap)
    }
}

/// Simple wrapping chip row without a third-party flow layout.
private struct FlexibleChipRow: View {
    let items: [String]
    var onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Button(item) { onTap(item) }
                            .buttonStyle(.plain)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Palette.accentSoft, in: Capsule())
                            .accessibilityIdentifier(ConversationPresence.chipAccessibilityID(item))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var rows: [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        var width = 0
        for item in items {
            let next = item.count
            if width + next > 28, !current.isEmpty {
                result.append(current)
                current = [item]
                width = next
            } else {
                current.append(item)
                width += next + 2
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

struct VoiceBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var composerFocused: Bool
    @State private var listeningPulse = false
    @State private var thinkingPulse = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Or say it here", text: $model.composerText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.line))
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { model.sendComposer() }
                    .accessibilityLabel("Type what you want to say")

                Button {
                    model.sendComposer()
                    composerFocused = false
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Palette.accent)
                }
                .disabled(model.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send typed turn")
            }

            if model.showsTalkCoach {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                    Text(ConversationPresence.talkHint)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .accessibilityIdentifier("voice.coach")
                .accessibilityLabel(ConversationPresence.talkHint)
            }

            Button(action: model.tapTalk) {
                VStack(spacing: 8) {
                    ZStack {
                        if model.voice.state == .listening {
                            Circle()
                                .stroke(Color.red.opacity(0.35), lineWidth: 4)
                                .frame(width: 98, height: 98)
                                .scaleEffect(listeningPulse ? 1.14 : 1)
                                .opacity(listeningPulse ? 0.35 : 0.9)
                        }
                        if model.voice.state == .thinking {
                            Circle()
                                .stroke(Palette.ink.opacity(0.28), lineWidth: 3)
                                .frame(width: 98, height: 98)
                                .scaleEffect(thinkingPulse ? 1.1 : 1)
                                .opacity(thinkingPulse ? 0.4 : 0.85)
                        }
                        Circle()
                            .fill(Palette.accentSoft)
                            .frame(width: 84, height: 84)
                            .scaleEffect(
                                model.voice.state == .listening
                                    || model.voice.state == .thinking
                                    || model.showsTalkCoach ? 1.1 : 1
                            )
                        Circle()
                            .fill(micFill)
                            .frame(width: 68, height: 68)
                        Image(systemName: micSymbol)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    .onChange(of: model.voice.state) { _, state in
                        listeningPulse = state == .listening
                        thinkingPulse = state == .thinking
                    }
                    .animation(
                        model.voice.state == .listening
                            ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.2),
                        value: listeningPulse
                    )
                    .animation(
                        model.voice.state == .thinking
                            ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                            : .easeOut(duration: 0.2),
                        value: thinkingPulse
                    )
                    Text(micLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("voice.talk")
            .accessibilityLabel(micLabel)
            .accessibilityHint("Talk to me. I’ll answer — cards only if it’s about your desk.")

            if let error = model.voice.lastError, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("voice.error")
            }

            Text(model.voice.needsCredentials
                 ? "Grok is not connected yet. Add a key to talk."
                 : (model.showsTalkCoach
                    ? "This is a voice assistant. Tap Talk and speak."
                    : "Tap when you want to talk. Ask anything."))
                .font(.caption2)
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var micFill: Color {
        switch model.voice.state {
        case .listening: Color.red.opacity(0.9)
        case .speaking: Palette.accent.opacity(0.85)
        case .thinking: Palette.ink.opacity(0.7)
        case .idle: Palette.accent
        }
    }

    private var micSymbol: String {
        switch model.voice.state {
        case .listening: "waveform"
        case .speaking: "speaker.wave.2.fill"
        case .thinking: "ellipsis"
        case .idle: "mic.fill"
        }
    }

    private var micLabel: String {
        if model.voice.needsCredentials {
            return "Set up Grok to talk"
        }
        switch model.voice.state {
        case .idle: return "Tap to talk"
        case .listening: return "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Speaking… tap to stop"
        }
    }
}

struct VoiceSetupBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect Grok to talk")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text("Set XAI_API_KEY in the VoiceDesk scheme, or copy Secrets.example.plist to Secrets.plist (gitignored). Without a key I will not pretend to listen.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityIdentifier("voice.setup")
        .accessibilityLabel("Connect Grok to talk. Set XAI_API_KEY or Secrets.plist.")
    }
}

struct ActivitySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.activity.isEmpty {
                    Text("Nothing’s been sent or scheduled. When you confirm a write, it shows up here — I won’t pretend it went through.")
                        .foregroundStyle(Palette.muted)
                } else {
                    ForEach(model.activity.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.headline)
                            Text(entry.detail)
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                            Text(entry.outcome)
                                .font(.footnote)
                            Text(entry.at.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Text(model.voice.backendLabel)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                    .accessibilityLabel("Voice backend")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Conversation") {
    ConversationScreen()
        .environment(AppModel())
}
