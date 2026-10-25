import SwiftUI

/// Today · Room · People · You. Owns the flow runtime and everything that must survive a tab switch:
/// the consent card, the readiness sheet, the volume-button trigger and the "just saved" detail sheet.
struct MainTabView: View {
    enum Tab: Hashable { case today, room, people, you }

    @EnvironmentObject var state: AppState
    @EnvironmentObject var coordinator: AppCoordinator
    @StateObject private var runtime = FlowRuntime()
    @AppStorage(UserSettings.readinessDone) private var readinessDone = false
    @AppStorage(UserSettings.volumePrimary) private var volumePrimary = "whoIsHere"
    @State private var tab: Tab = .today
    @State private var showReadiness = false
    @State private var savedPerson: Person?
    @State private var previewConsentCard = ProcessInfo.processInfo.arguments.contains("-demoConsentCard")

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView().environmentObject(runtime) }
                .tabItem { Label("Today", systemImage: "sparkles") }
                .tag(Tab.today)
            NavigationStack { RoomView().environmentObject(runtime) }
                .tabItem { Label("Room", systemImage: "person.2") }
                .tag(Tab.room)
            NavigationStack { PeopleView().environmentObject(runtime) }
                .tabItem { Label("People", systemImage: "person.crop.rectangle.stack") }
                .tag(Tab.people)
            NavigationStack { YouView().environmentObject(runtime) }
                .tabItem { Label("You", systemImage: "person.circle") }
                .tag(Tab.you)
        }
        .tint(FamiliarPalette.ocean)
        .environment(\.openReadiness, { showReadiness = true })
        .background(VolumeButtonObserver { pressed in
            guard pressed else { return }
            if volumePrimary == "rememberThem" { rememberThem() } else { whoIsHere() }
        })
        .fullScreenCover(isPresented: Binding(get: { runtime.showsConsentCard }, set: { if !$0 { runtime.cancelConsent() } })) {
            ConsentCardView(state: runtime.consentState,
                            question: consentQuestion,
                            onAnswer: { runtime.tapAnswer(yes: $0) },
                            onCancel: { runtime.cancelConsent() },
                            levelProvider: { Double(coordinator.services?.audioInput.micLevel ?? 0) })
        }
        .fullScreenCover(isPresented: $previewConsentCard) {
            ConsentCardView(state: .listening,
                            question: Phrasebook.consentQuestion(userName: state.userName, name: "Marcus"),
                            onAnswer: { _ in previewConsentCard = false },
                            onCancel: { previewConsentCard = false })
        }
        .sheet(isPresented: $showReadiness) { ReadinessView(onDone: { showReadiness = false; readinessDone = true }) }
        .sheet(item: $savedPerson) { person in
            NavigationStack { PersonDetailView(person: person).environmentObject(runtime) }
        }
        .onReceive(coordinator.$services) { services in
            if let services { runtime.bind(services: services, state: state, coordinator: coordinator) }
        }
        .onChange(of: runtime.lastSaved) { _, person in
            if let person { savedPerson = person }
        }
        .onAppear { if !readinessDone { showReadiness = true } }
    }

    private func whoIsHere() { if runtime.router != nil { runtime.whoIsHere() } else { coordinator.whoIsHere() } }
    private func rememberThem() { if runtime.router != nil { runtime.rememberThem() } else { coordinator.rememberThem() } }

    private var consentQuestion: String {
        if case let .asking(name) = runtime.consentState { return Phrasebook.consentQuestion(userName: state.userName, name: name) }
        return Phrasebook.consentQuestion(userName: state.userName, name: runtime.nameGuess?.name)
    }
}

/// Lets any screen open the readiness checklist (the device chip on Today uses it).
private struct OpenReadinessKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openReadiness: () -> Void {
        get { self[OpenReadinessKey.self] }
        set { self[OpenReadinessKey.self] = newValue }
    }
}

/// The You tab: who you are, how Familiar speaks, and the diagnostics the judges might ask for.
struct YouView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var runtime: FlowRuntime
    @Environment(\.openReadiness) private var openReadiness

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Monogram(name: state.userName, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.userName).font(FamiliarType.title).foregroundStyle(FamiliarPalette.ink)
                        Text("\(runtime.people.count) people chose to connect").font(FamiliarType.supporting).foregroundStyle(FamiliarPalette.inkSecondary)
                    }
                }
                .surfaceCard()
                .accessibilityElement(children: .combine)

                VStack(spacing: 0) {
                    NavigationLink { SettingsView() } label: { row("Voice and cues", "speaker.wave.2", "Quiet, normal or chatty; voice; thresholds") }
                    Divider().padding(.leading, 56)
                    Button(action: openReadiness) { row("Device and permissions", "checklist", "Glasses, camera, microphone, contacts") }
                    Divider().padding(.leading, 56)
                    NavigationLink { DemoControlsView() } label: { row("Demo controls", "wand.and.stars", "Scripted helpers for the table") }
                }
                .surfaceCard(padding: 6)

                PrivacyBanner(text: JudgeView.banner)
                Text("Removing a person deletes their record, thumbnail, consent clip and the contact this app created. Only text ever leaves the phone.")
                    .font(FamiliarType.supporting)
                    .foregroundStyle(FamiliarPalette.inkSecondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, FamiliarPalette.margin)
            .padding(.vertical, 12)
        }
        .familiarCanvas()
        .navigationTitle("You")
    }

    private func row(_ title: String, _ symbol: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(FamiliarPalette.ocean).frame(width: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FamiliarType.body.weight(.medium)).foregroundStyle(FamiliarPalette.ink)
                Text(detail).font(FamiliarType.supporting).foregroundStyle(FamiliarPalette.inkSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(FamiliarPalette.inkSecondary).accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}
