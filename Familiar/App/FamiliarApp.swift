import SwiftUI

@main
struct FamiliarApp: App {
    @StateObject private var state = AppState()
    @StateObject private var coordinator = AppCoordinator()
    private let showGlassesOnLaunch = ProcessInfo.processInfo.arguments.contains("--glasses")

    init() { GlassesSDK.configureIfNeeded() }

    var body: some Scene {
        WindowGroup {
            Group {
                if showGlassesOnLaunch {
                    NavigationStack { GlassesRegistrationView() }
                } else {
                    RootView()
                }
            }
            .environmentObject(state)
            .environmentObject(coordinator)
            .task { await coordinator.boot(state: state) }
            .onOpenURL { url in
                if GlassesSDK.isCallbackURL(url) { Task { await GlassesSDK.handle(url: url) } }
                coordinator.handle(url: url)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if coordinator.isReady { HomeView() } else { ReadinessView() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { coordinator.appBecameActive() } }
    }
}
