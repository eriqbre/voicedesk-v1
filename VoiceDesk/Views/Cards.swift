import SwiftUI
import VoiceDeskLogic

struct ContentCardView: View {
    let card: ContentCard

    var body: some View {
        Group {
            switch card {
            case .email(let item): EmailCardView(item: item)
            case .listing(let item): ListingCardView(item: item)
            case .person(let item): PersonCardView(item: item)
            case .draftConfirm(let item): DraftConfirmCardView(item: item)
            case .statute(let item): StatuteCardView(item: item)
            case .connectGoogle(let item): ConnectGoogleCardView(item: item)
            case .calendar(let item): CalendarCardView(item: item)
            case .task(let item): TaskCardView(item: item)
            }
        }
        // Outer ID is what made CI green (91b54e4). CardChrome must stay visual-only.
        .accessibilityIdentifier(card.fixtureID)
    }
}

struct CardChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.line)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
    }
}

struct EmailCardView: View {
    @Environment(AppModel.self) private var model
    let item: EmailItem
    @State private var showingEarlier = false

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    InitialsMark(initials: item.initials, hue: 0.72)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(item.fromName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text(item.sentAtLabel)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        Text(item.fromEmail)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }
                Text(item.subject)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                if item.hasFullBody {
                    EmailBodyReader(html: item.htmlBody, plain: item.body, expandsToFit: true)
                } else {
                    Text(item.preview)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink.opacity(0.85))
                        .lineLimit(3)
                }
                if item.hasEarlierMessages {
                    Button(showingEarlier ? "Hide earlier messages" : "Show earlier messages") {
                        showingEarlier.toggle()
                    }
                    .buttonStyle(SecondaryCardButton())
                    .accessibilityIdentifier("email.thread.toggle")
                    if showingEarlier {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(item.earlierMessages) { message in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(message.fromName)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Palette.ink)
                                        Spacer()
                                        if !message.sentAtLabel.isEmpty {
                                            Text(message.sentAtLabel)
                                                .font(.caption2)
                                                .foregroundStyle(Palette.muted)
                                        }
                                    }
                                    EmailBodyReader(html: message.htmlBody, plain: message.plainBody, expandsToFit: false)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                if item.providerID != nil, model.google.isConnected {
                    Button(item.hasFullBody ? "Refresh email" : "Read email") { model.openEmail(item) }
                        .buttonStyle(SecondaryCardButton())
                        .accessibilityIdentifier("email.read")
                }
                HStack(spacing: 8) {
                    TagChip(text: item.filterTag, systemImage: "tray")
                    if let listing = item.relatedListing {
                        TagChip(text: listing, systemImage: "house")
                    }
                }
                if !item.relatedPeople.isEmpty {
                    Text("People  \(item.relatedPeople.joined(separator: " · "))")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(emailAccessibilityLabel)
        .accessibilityIdentifier("card.email")
    }

    private var emailAccessibilityLabel: String {
        if let body = item.body, item.hasFullBody {
            return "Email from \(item.fromName). \(item.subject). \(body)"
        }
        return "Email from \(item.fromName). \(item.subject). \(item.preview)"
    }
}

struct ListingCardView: View {
    let item: ListingItem

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.62, blue: 0.88),
                                    Color(red: 0.78, green: 0.52, blue: 0.46)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 128)
                        .overlay {
                            Image(systemName: "house.lodge.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Color.white.opacity(0.28))
                        }
                    HStack(spacing: 8) {
                        StatusPill(text: item.status)
                        StatusPill(text: item.ownership, muted: true)
                    }
                    .padding(10)
                }
                Text(item.priceLabel)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text(item.addressLine)
                    .font(.headline)
                Text(item.cityLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                HStack(spacing: 14) {
                    Meta(item.beds, "bd")
                    Meta(item.baths, "ba")
                    Meta(item.sqft, "sqft")
                }
                .font(.subheadline.weight(.medium))
                if !item.relatedPeople.isEmpty {
                    Text(item.relatedPeople.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Listing \(item.addressLine), \(item.priceLabel), \(item.beds) beds, \(item.baths) baths.")
        .accessibilityIdentifier("card.listing")
    }

    private func Meta(_ value: Int, _ unit: String) -> some View {
        Text("\(value.formatted()) \(unit)")
            .foregroundStyle(Palette.ink)
    }
}

struct PersonCardView: View {
    @Environment(AppModel.self) private var model
    let item: PersonItem

    var body: some View {
        CardChrome {
            HStack(alignment: .center, spacing: 12) {
                InitialsMark(initials: item.initials, hue: item.accentHue, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.headline)
                    Text(item.roleLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                VStack(spacing: 8) {
                    IconAction(systemImage: "phone.fill") { model.handlePersonCall(item) }
                        .accessibilityLabel("Call \(item.name)")
                    IconAction(systemImage: "message.fill") { model.handlePersonMessage(item) }
                        .accessibilityLabel("Message \(item.name)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.name), \(item.roleLabel). \(item.detail)")
        .accessibilityIdentifier("card.person")
    }
}

struct DraftConfirmCardView: View {
    @Environment(AppModel.self) private var model
    let item: DraftConfirmItem
    @State private var draftBody: String = ""

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Review before sending", systemImage: "checkmark.shield")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    Spacer()
                    Text(item.channel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
                Text(item.actionTitle)
                    .font(.headline)
                labeled("To", item.toLine)
                labeled("Subject", item.subject)
                if item.status == .editing {
                    Text("Body")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                    TextField("Message", text: $draftBody, axis: .vertical)
                        .lineLimit(4...10)
                        .padding(10)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Text(item.body)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink.opacity(0.9))
                }
                statusLine
                if item.status == .pending || item.status == .editing {
                    HStack(spacing: 10) {
                        Button("Confirm & Send") {
                            if item.status == .editing {
                                model.saveDraftBody(item.id, body: draftBody)
                            }
                            model.confirmDraft(item.id)
                        }
                        .buttonStyle(PrimaryCardButton())
                        .accessibilityIdentifier("draft.confirm")
                        if item.status == .editing {
                            Button("Save edit") {
                                model.saveDraftBody(item.id, body: draftBody)
                            }
                            .buttonStyle(SecondaryCardButton())
                        } else {
                            Button("Edit") {
                                draftBody = item.body
                                model.beginEditDraft(item.id)
                            }
                            .buttonStyle(SecondaryCardButton())
                        }
                        Button("Cancel") { model.cancelDraft(item.id) }
                            .buttonStyle(SecondaryCardButton())
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Draft \(item.actionTitle) to \(item.toLine). \(item.subject).")
        .accessibilityIdentifier("card.draftConfirm")
        .onAppear { draftBody = item.body }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch item.status {
        case .pending, .editing:
            Text("Nothing sends until you confirm. This slice will not deliver to Gmail.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        case .confirmed:
            Text("Confirmed — logged on Activity. Not sent.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .accessibilityIdentifier("draft.queued")
        case .cancelled:
            Text("Cancelled. Nothing was sent.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.subheadline)
        }
    }
}

struct StatuteCardView: View {
    let item: StatuteItem

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Statute / confidence")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                    Spacer()
                    Text(item.band.label)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(bandColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(bandColor)
                }
                Text(item.title)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Confidence")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        Text("\(item.confidence)%")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.ink)
                    }
                    ProgressView(value: Double(item.confidence), total: 100)
                        .tint(bandColor)
                        .accessibilityLabel("Confidence \(item.confidence) percent")
                }
                Text(item.plainLanguage)
                    .font(.subheadline)
                Text(item.citation)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                Text(item.disclaimer)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). Confidence \(item.confidence) percent, \(item.band.label). \(item.citation).")
        .accessibilityIdentifier("card.statute")
    }

    private var bandColor: Color {
        switch item.band {
        case .firm: Color(red: 0.16, green: 0.55, blue: 0.38)
        case .options: Color(red: 0.78, green: 0.48, blue: 0.12)
        case .unknown: Color(red: 0.66, green: 0.22, blue: 0.22)
        }
    }
}

struct ConnectGoogleCardView: View {
    @Environment(AppModel.self) private var model
    let item: ConnectGoogleItem

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Palette.line)
                            )
                        Text("G")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Palette.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.headline)
                            .font(.headline)
                        Text(item.statusLine)
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }
                Text(item.setupNeeded
                    ? (model.google.snapshot.message ?? GoogleAuthSnapshot.missingClientIDCopy)
                    : item.body)
                    .font(.subheadline)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Gmail — read now; send only after confirm", systemImage: "envelope")
                    Label("Calendar — upcoming events", systemImage: "calendar")
                    Label("Tasks — open items", systemImage: "checkmark.circle")
                }
                .font(.caption)
                .foregroundStyle(Palette.ink.opacity(0.8))
                if item.setupNeeded {
                    Text("I am not connected. Add GOOGLE_CLIENT_ID, then try again.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                        .accessibilityIdentifier("google.setup")
                } else if item.isConnected || model.google.isConnected {
                    if let email = item.accountEmail ?? model.google.snapshot.email {
                        Text(email)
                            .font(.caption.weight(.semibold))
                            .accessibilityIdentifier("google.account")
                    }
                    Button("Disconnect") { model.disconnectGoogle() }
                        .buttonStyle(SecondaryCardButton())
                        .accessibilityIdentifier("google.disconnect")
                } else {
                    Button("Connect Google") { model.connectGoogle() }
                        .buttonStyle(PrimaryCardButton())
                        .accessibilityIdentifier("google.connect")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.headline)
        .accessibilityIdentifier("card.connectGoogle")
    }
}

struct CalendarCardView: View {
    let item: CalendarItem
    @State private var showingDetails = true

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 10) {
                Label("Calendar", systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                Text(item.title)
                    .font(.headline)
                labeled("When", item.whenLabel)
                if item.hasDetails {
                    Button(showingDetails ? "Hide details" : "Show details") {
                        showingDetails.toggle()
                    }
                    .buttonStyle(SecondaryCardButton())
                    .accessibilityIdentifier("calendar.details.toggle")
                }
                if showingDetails {
                    calendarDetails
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityIdentifier("card.calendar")
    }

    @ViewBuilder
    private var calendarDetails: some View {
        if let location = item.location, !location.isEmpty {
            labeled("Location", location)
                .accessibilityIdentifier("calendar.location")
        }
        if !item.relatedPeople.isEmpty {
            labeled("People", item.relatedPeople.joined(separator: " · "))
                .accessibilityIdentifier("calendar.people")
        }
        if let notes = item.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("calendar.notes")
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
        }
    }
}

struct TaskCardView: View {
    let item: TaskItem

    var body: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 8) {
                Label("Task", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                Text(item.title)
                    .font(.headline)
                if let due = item.dueLabel {
                    Text(due)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink.opacity(0.85))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task \(item.title).")
        .accessibilityIdentifier("card.task")
    }
}

struct InitialsMark: View {
    let initials: String
    var hue: Double
    var size: CGFloat = 40

    var body: some View {
        Text(initials)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(Color(hue: hue, saturation: 0.45, brightness: 0.72), in: Circle())
            .accessibilityHidden(true)
    }
}

struct TagChip: View {
    let text: String
    var systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Palette.background, in: Capsule())
            .foregroundStyle(Palette.ink.opacity(0.8))
    }
}

struct StatusPill: View {
    let text: String
    var muted = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(muted ? 0.35 : 0.5), in: Capsule())
            .foregroundStyle(Color.white)
    }
}

struct IconAction: View {
    let systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 32, height: 32)
                .background(Palette.accentSoft, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct PrimaryCardButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

struct SecondaryCardButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Palette.background.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
    }
}

#Preview("Cards") {
    ScrollView {
        VStack(spacing: 16) {
            EmailCardView(item: SampleData.email())
            ListingCardView(item: SampleData.listing())
            PersonCardView(item: SampleData.buyer())
            DraftConfirmCardView(item: SampleData.draftReply())
            StatuteCardView(item: SampleData.statute())
            ConnectGoogleCardView(item: SampleData.connectGoogle())
            CalendarCardView(item: SampleData.calendarEvent())
            TaskCardView(item: SampleData.openTask())
        }
        .padding()
    }
    .background(Palette.background)
    .environment(AppModel())
}
