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
    var body: some View {
        if coordinator.isReady { HomeView() } else { ReadinessView() }
    }
}
