import SwiftUI
import UIKit

/// Your people: everyone who said yes, as white cards on the ivory canvas. Search filters by name, the chips
/// show All or Recent (the last 24 hours), a swipe asks before removing, and the gooey plus menu adds someone
/// (ask them out loud, or read how the invitation will work). Removal deletes the record, thumbnail, consent clip
/// and the iOS contact, exactly as before.
struct PeopleView: View {
    @EnvironmentObject var runtime: FlowRuntime
    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var query = ""
    @State private var filter: PeopleFilter = .all
    @State private var selection: PersonSelection?
    @State private var showMap = false
    @State private var showInvitation = false
    @State private var pendingRemoval: Person?
    @State private var toast: PeopleRemovalToast?

    private static let filterOptions: [(PeopleFilter, String)] = [(.all, "All"), (.recent, "Recent")]

    var body: some View {
        List {
            PeopleHeader(count: runtime.people.count, onShowMap: { showMap = true })
                .peopleRow(top: 12, bottom: 4)
            PeopleSearchField(text: $query)
                .peopleRow(top: 6, bottom: 2)
            SlidingPillSegment(options: Self.filterOptions, selection: $filter, label: "Filter people, all or the last day")
                .peopleRow(top: 4, bottom: 8)

            if runtime.people.isEmpty {
                PeopleEmptyState(onAsk: rememberThem, onInvite: { showInvitation = true })
                    .peopleRow(top: 8, bottom: 8)
            } else if filtered.isEmpty {
                PeopleNoMatch(query: query, filter: filter, onClear: clearFilters)
                    .peopleRow(top: 8, bottom: 8)
            } else {
                ForEach(filtered) { person in
                    personRow(person)
                }
            }

            // Room for the floating menu so the last card is never covered.
            Color.clear
                .frame(height: 120)
                .peopleRow(top: 0, bottom: 0)
                .accessibilityHidden(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .animation(motion(FamiliarMotion.spring), value: filteredIDs)
        .familiarCanvas()
        .navigationTitle("People")   // hidden here; names the Back button on pushed screens
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottomTrailing) { addMenu }
        .overlay(alignment: .bottom) { toastOverlay }
        .navigationDestination(item: $selection) { (sel: PersonSelection) in
            PersonDetailView(person: sel.person)
        }
        .navigationDestination(isPresented: $showMap) {
            PlacesMapView(people: runtime.people)
        }
        .sheet(isPresented: $showInvitation) {
            InvitationSheet(userName: state.userName, onAsk: rememberThem)
        }
        .confirmationDialog(removalTitle, isPresented: removalPresented, titleVisibility: .visible) {
            if let person = pendingRemoval {
                Button("Remove \(person.name)", role: .destructive) { remove(person) }
            }
            Button("Keep", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("This deletes the face data, thumbnail, consent clip and the contact this app created.")
        }
        .onAppear { runtime.refreshPeople() }
    }

    // MARK: - Rows

    /// The whole card is the button; `liftOnPress` gives it the 0.97 squeeze from the motion library (still under
    /// Reduce Motion), so every pressed card in the app moves the same way.
    private func personRow(_ person: Person) -> some View {
        Button { selection = PersonSelection(person: person) } label: {
            PersonRowCard(person: person, image: runtime.thumbnail(for: person))
        }
        .buttonStyle(.plain)
        .liftOnPress()
        .accessibilityHint("Shows details, call and text, and removal")
        .peopleRow(top: 8, bottom: 8)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { pendingRemoval = person } label: { Label("Remove", systemImage: "trash") }
                .accessibilityLabel("Remove \(person.name)")
                .accessibilityHint("Asks first, then deletes the face, consent clip and contact")
        }
    }

    private var addMenu: some View {
        GooeyMenu(systemImage: "plus", label: "Add someone", items: [
            GooeyMenuItem(title: "Ask them out loud", systemImage: "waveform", action: rememberThem),
            GooeyMenuItem(title: "Show invitation", systemImage: "qrcode", action: { showInvitation = true })
        ])
        .padding(.trailing, FamiliarPalette.margin)
        .padding(.bottom, 12)
    }

    /// The removal confirmation rises from the bottom (CueToast's own transition), above the gooey menu and clear of
    /// the spoken-cue toast that `MainTabView` shows at the top.
    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            CueToast(text: toast.text, systemImage: "checkmark", tint: FamiliarPalette.ink)
                .padding(.horizontal, FamiliarPalette.margin)
                .padding(.bottom, scale.hitTarget + 36)
                .accessibilityHidden(true)   // announced separately, once
        }
    }

    // MARK: - Motion

    private var animates: Bool { FamiliarMotion.animates(scale, reduceMotion: reduceMotion) }

    /// `nil` (an instant cut) when the profile or the system asks for less motion.
    private func motion(_ animation: Animation) -> Animation? { animates ? animation : nil }

    // MARK: - Filtering

    private var filtered: [Person] {
        let now = Date()
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return runtime.people
            .filter { person in
                filter == .all || person.isRecent(now: now)
            }
            .filter { person in
                needle.isEmpty || person.name.lowercased().contains(needle)
            }
            .sorted { $0.met.at > $1.met.at }
    }

    private var filteredIDs: [UUID] { filtered.map { $0.id } }

    private func clearFilters() {
        withAnimation(motion(FamiliarMotion.diffusion)) {
            query = ""
            filter = .all
        }
    }

    // MARK: - Actions

    /// Same path as Today and the volume button: the runtime once services are bound, the coordinator before that.
    private func rememberThem() {
        if runtime.router != nil { runtime.rememberThem() } else { coordinator.rememberThem() }
    }

    // MARK: - Removal

    private var removalTitle: Text {
        Text("Remove \(pendingRemoval?.name ?? "this person")? This deletes everything about them.")
    }

    private var removalPresented: Binding<Bool> {
        Binding<Bool>(get: { pendingRemoval != nil }, set: { shown in if !shown { pendingRemoval = nil } })
    }

    private func remove(_ person: Person) {
        runtime.remove(person)
        pendingRemoval = nil
        FamiliarHaptics.play(.accepted)
        let info = PeopleRemovalToast(text: "Removed \(person.name)")
        withAnimation(motion(CueToast.spring())) { toast = info }
        UIAccessibility.post(notification: .announcement, argument: "Removed \(person.name). Everything about them was deleted from this phone.")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            if toast?.id == info.id {
                withAnimation(motion(CueToast.spring())) { toast = nil }
            }
        }
    }
}

/// One removal confirmation, shown for a few seconds above the menu.
private struct PeopleRemovalToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

// MARK: - Header, search, states

/// "Your people" / "Only people who said yes." with the count and the map control. The title and the control sit
/// side by side on the balanced design and stack from the severe profile or accessibility Dynamic Type sizes.
private struct PeopleHeader: View {
    let count: Int
    let onShowMap: () -> Void
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var stacked: Bool { typeSize.isAccessibilitySize || scale.prefersStackedLayout }

    private var layout: AnyLayout {
        stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: scale.spacing(10)))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            layout {
                Text("Your people")
                    .font(FamiliarType.titleXL(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                    .accessibilityAddTraits(.isHeader)
                if !stacked { Spacer(minLength: 8) }
                Button(action: onShowMap) { Label("Where you met", systemImage: "map") }
                    .buttonStyle(PeopleCompactPillStyle())
                    .accessibilityHint("Shows a map of the places where people said yes")
            }
            HStack(spacing: 10) {
                Text("Only people who said yes.")
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                if count > 0 { countChip }
            }
        }
    }

    private var countChip: some View {
        HStack(spacing: 4) {
            NumberPop(value: count, font: FamiliarType.micro(scale), color: FamiliarPalette.inkSecondary(scale))
            Text(count == 1 ? "person" : "people")
                .font(FamiliarType.micro(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(count == 1 ? "person" : "people")")
    }
}

/// A small white pill for a secondary control in a header. Draws compact, but its tappable area always meets the
/// profile's hit target; the press squeeze obeys Reduce Motion. The label wraps rather than truncates (rule 1): at
/// accessibility sizes the header stacks and gives it the full width.
private struct PeopleCompactPillStyle: ButtonStyle {
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FamiliarType.supporting(scale))
            .foregroundStyle(FamiliarPalette.ink(scale))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, scale.spacing(14))
            .padding(.vertical, scale.spacing(9))
            .background(FamiliarPalette.surface(scale), in: Capsule())
            .overlay(Capsule().strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
            .frame(minHeight: scale.hitTarget)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && FamiliarMotion.animates(scale, reduceMotion: reduceMotion) ? 0.97 : 1)
            .animation(FamiliarMotion.tap, value: configuration.isPressed)
    }
}

/// A pill search field: magnifier, name filter, clear button. Persistent label for VoiceOver.
private struct PeopleSearchField: View {
    @Binding var text: String
    @Environment(\.visionScale) private var scale

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .visionIcon(scale, base: 17)
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .accessibilityHidden(true)
            TextField("Search by name", text: $text)
                .font(FamiliarType.body(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search your people")
                .accessibilityHint("Filters the list by name")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .visionIcon(scale, base: 18)
                        .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                }
                .buttonStyle(.plain)
                .visionHitTarget(scale)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, text.isEmpty ? 18 : 6)
        .frame(minHeight: scale.hitTarget)
        .background(FamiliarPalette.surface(scale), in: Capsule())
        .overlay(Capsule().strokeBorder(FamiliarPalette.stroke(scale), lineWidth: scale.strokeWidth))
    }
}

/// No one yet: a small Mimo, the line from the spec, and the two ways to add someone.
private struct PeopleEmptyState: View {
    let onAsk: () -> Void
    let onInvite: () -> Void
    @Environment(\.visionScale) private var scale

    var body: some View {
        VStack(spacing: 16) {
            MimoView(state: .idle, size: 120)
            Text("The best connections start with a hello.")
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("When someone says yes, they appear here. Nothing is saved before that.")
                .font(FamiliarType.supporting(scale))
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .multilineTextAlignment(.center)
            Button(action: onAsk) { Label("Ask them out loud", systemImage: "waveform") }
                .buttonStyle(PrimaryPillStyle())
                .accessibilityHint("Asks the person in front of you for permission to remember their face")
            Button(action: onInvite) { Label("Show invitation", systemImage: "qrcode") }
                .buttonStyle(GhostPillStyle())
                .accessibilityHint("Explains the tap-to-join page that is coming later")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .surfaceCard(radius: FamiliarPalette.heroRadius, padding: 24)
    }
}

/// People exist, but nothing matches the search or the Recent chip.
private struct PeopleNoMatch: View {
    let query: String
    let filter: PeopleFilter
    let onClear: () -> Void
    @Environment(\.visionScale) private var scale

    private var headline: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return "No one called “\(trimmed)”." }
        return "No one new in the last day."
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .visionIcon(scale, base: 30)
                .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                .accessibilityHidden(true)
            Text(headline)
                .font(FamiliarType.title(scale))
                .foregroundStyle(FamiliarPalette.ink(scale))
                .multilineTextAlignment(.center)
            Button(action: onClear) { Text("Show everyone") }
                .buttonStyle(GhostPillStyle())
                .accessibilityHint("Clears the search and the Recent filter")
        }
        .frame(maxWidth: .infinity)
        .surfaceCard(padding: 24)
        .cardResize()
    }
}

// MARK: - Row card

/// One person: photo or monogram, name, where and when you met, "Opted in". A single VoiceOver element.
struct PersonRowCard: View {
    let person: Person
    let image: UIImage?
    @Environment(\.visionScale) private var scale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var stacked: Bool { typeSize.isAccessibilitySize || scale.prefersStackedLayout }

    private var layout: AnyLayout {
        stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 14))
    }

    var body: some View {
        layout {
            Thumb(image: image, name: person.name, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(FamiliarType.title(scale))
                    .foregroundStyle(FamiliarPalette.ink(scale))
                    .lineLimit(2)
                Text(person.metLine)
                    .font(FamiliarType.supporting(scale))
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !stacked { Spacer(minLength: 8) }
            HStack(spacing: 8) {
                StatusChip(text: "Opted in", systemImage: "checkmark.seal.fill", tint: FamiliarPalette.success)
                Image(systemName: "chevron.right")
                    .visionIcon(scale, base: 13)
                    .foregroundStyle(FamiliarPalette.inkSecondary(scale))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(padding: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.name). \(person.metLine). Opted in.")
    }
}

private extension View {
    /// A list row that behaves like a card on the canvas: no separator, no background, canvas margins.
    func peopleRow(top: CGFloat, bottom: CGFloat) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: FamiliarPalette.margin, bottom: bottom, trailing: FamiliarPalette.margin))
    }
}

// MARK: - Previews

#Preview("People, empty") {
    NavigationStack { PeopleView() }
        .environmentObject(FlowRuntime())
        .environmentObject(AppState())
        .environmentObject(AppCoordinator())
}

#Preview("Person rows") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(PeoplePreviewData.people) { person in
                PersonRowCard(person: person, image: nil)
            }
        }
        .padding(FamiliarPalette.margin)
    }
    .familiarCanvas()
}
