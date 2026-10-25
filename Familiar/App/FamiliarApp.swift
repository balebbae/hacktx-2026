import SwiftUI

@main
struct FamiliarApp: App {
    @StateObject private var state = AppState()
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(coordinator)
                .task { await coordinator.boot(state: state) }
                .onOpenURL { url in coordinator.handle(url: url) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    var body: some View {
        if coordinator.isReady { HomeView() } else { ReadinessView() }
    }
}
