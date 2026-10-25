import XCTest
import SwiftUI
import UIKit
@testable import Familiar

/// Renders the demo screens to PNG so people without Xcode can look at them, once at the balanced vision scale and
/// once at the severe one. Run:
///   SNAPSHOT_DIR=$PWD/docs/snapshots xcodebuild -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17' \
///     -only-testing:FamiliarTests/SnapshotRenderTests CODE_SIGNING_ALLOWED=NO test
/// The PNGs are also attached to the test report. Canvas and TimelineView animations do not advance under
/// `ImageRenderer`, so Mimo, the aurora and the beams render their still frames.
@MainActor
final class SnapshotRenderTests: XCTestCase {
    func testRenderDemoScreens() throws {
        let outputDir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]
        if let outputDir { try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true) }
        let defaults = UserDefaults(suiteName: "SnapshotRenderTests")!
        let state = AppState(defaults: defaults)
        let coordinator = AppCoordinator()
        let runtime = FlowRuntime()

        func wired<V: View>(_ view: V) -> AnyView {
            AnyView(view
                .environmentObject(state)
                .environmentObject(coordinator)
                .environmentObject(runtime))
        }

        let screens: [(String, AnyView)] = [
            ("welcome", wired(SnapshotScreens.welcome())),
            ("today", wired(HomeView())),
            ("room-radar", wired(SnapshotScreens.roomRadar(tracks: SnapshotSamples.tracks))),
            ("people-empty", wired(PeopleView())),
            ("consent-card", wired(ConsentCardView(state: .listening,
                                                   question: Phrasebook.consentQuestion(userName: "Priya", name: "Marcus"),
                                                   onAnswer: { _ in }, onCancel: {}))),
            ("accessibility-settings", wired(AccessibilitySettingsView())),
            ("mimo", AnyView(VStack(spacing: 24) {
                MimoView(state: .idle, size: 200)
                MimoStatusLine(state: .idle)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).familiarCanvas())),
        ]
        let scales: [(String, VisionScale)] = [
            ("balanced", VisionScale.make(.balanced)),
            ("severe", VisionScale.make(.severe)),
        ]

        for (scaleName, scale) in scales {
            for (name, view) in screens {
                let fileName = "\(name)-\(scaleName)"
                let content = view
                    .environment(\.visionScale, scale)
                    .frame(width: 393, height: 852)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let image = renderer.uiImage, let png = image.pngData() else {
                    XCTFail("No image rendered for \(fileName)")
                    continue
                }
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = fileName
                attachment.lifetime = .keepAlways
                add(attachment)
                if let outputDir {
                    try png.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent("\(fileName).png"))
                }
            }
        }
    }
}

/// The two screens owned by other sessions, behind one function each so a renamed type is a one-line fix here.
enum SnapshotScreens {
    /// Onboarding session: the first page of the welcome flow (Mimo, "Because everyone deserves to feel seen.", motto).
    static func welcome() -> some View {
        WelcomePage()
    }

    /// TodayRoom session: the half-circle spatial map with five bands and three distance rings.
    static func roomRadar(tracks: [TrackSnapshot]) -> some View {
        RoomRadarView(tracks: tracks)
            .padding(FamiliarPalette.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .familiarCanvas()
    }
}

enum SnapshotSamples {
    static var tracks: [TrackSnapshot] {
        [
            TrackSnapshot(trackID: 1, identity: .known(personID: UUID(), name: "Marcus", score: 0.71),
                          bearing: Bearing(degrees: -4, band: .ahead), distance: .close,
                          faceBox: CGRect(x: 0.36, y: 0.22, width: 0.28, height: 0.26), faceHeightPx: 230,
                          yawDegrees: 3, isFacingUser: true, mouthOpenness: 0.1, quality: 0.8, timestamp: 0),
            TrackSnapshot(trackID: 2, identity: .unknown(bestScore: 0.21),
                          bearing: Bearing(degrees: 18, band: .right), distance: .medium,
                          faceBox: CGRect(x: 0.70, y: 0.30, width: 0.16, height: 0.15), faceHeightPx: 120,
                          yawDegrees: -20, isFacingUser: false, mouthOpenness: nil, quality: 0.5, timestamp: 0),
            TrackSnapshot(trackID: 3, identity: .known(personID: UUID(), name: "Maya", score: 0.66),
                          bearing: Bearing(degrees: -21, band: .farLeft), distance: .far,
                          faceBox: CGRect(x: 0.06, y: 0.34, width: 0.09, height: 0.08), faceHeightPx: 68,
                          yawDegrees: 12, isFacingUser: true, mouthOpenness: nil, quality: 0.6, timestamp: 0),
        ]
    }
}
