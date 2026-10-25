import SwiftUI

@main
struct FamiliarApp: App {
    @StateObject private var state = AppState()
    @StateObject private var coordinator = AppCoordinator()
    @AppStorage(OnboardingFlow.storageKey) private var onboardingDone = false
    private let showGlassesOnLaunch = ProcessInfo.processInfo.arguments.contains("--glasses")

    init() {
        GlassesSDK.configureIfNeeded()
        FamiliarHaptics.prepare()   // start the Core Haptics engine early so the first cue's tap is not late
        // `--onboarding` replays the first-launch flow (demo table, screenshots). It only clears the one flag.
        if ProcessInfo.processInfo.arguments.contains("--onboarding") {
            UserDefaults.standard.set(false, forKey: OnboardingFlow.storageKey)
        }
    }

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
            .visionProfile(state.visionProfile)   // resolves VisionScale for the whole tree, system accessibility settings folded in
            // The pipeline (camera, microphone, speech) boots once onboarding is done, so the system permission
            // prompts arrive from the readiness checklist with context, never over the Welcome page. `boot` is
            // idempotent, so re-running the task when the flag flips is safe. `--glasses` boots at once as before.
            .task(id: onboardingDone) {
                guard onboardingDone || showGlassesOnLaunch else { return }
                await coordinator.boot(state: state)
            }
            .onOpenURL { url in
                if GlassesSDK.isCallbackURL(url) { Task { await GlassesSDK.handle(url: url) } }
                coordinator.handle(url: url)
            }
        }
    }
}

/// First launch shows the onboarding flow; afterwards the tab bar, with the readiness checklist while the coordinator boots.
struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @AppStorage(OnboardingFlow.storageKey) private var onboardingDone = false
    @Environment(\.visionScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if !onboardingDone {
                OnboardingFlow()
                    .transition(.opacity)
            } else if coordinator.isReady {
                MainTabView()
                    .transition(.opacity)
            } else {
                ReadinessView()
                    .transition(.opacity)
            }
        }
        .animation(crossfade, value: onboardingDone)
        .animation(crossfade, value: coordinator.isReady)
        .onChange(of: scenePhase) { _, phase in if phase == .active { coordinator.appBecameActive() } }
    }

    private var crossfade: Animation? {
        (reduceMotion || scale.simplifyMotion) ? nil : .easeInOut(duration: 0.35)
    }
}
