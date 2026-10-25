import XCTest
import SwiftUI
import UIKit
@testable import Familiar

/// Renders the demo screens to PNG so people without Xcode can look at them. Run:
///   SNAPSHOT_DIR=$PWD/docs/snapshots xcodebuild -scheme Familiar -destination 'platform=iOS Simulator,name=iPhone 17' \
///     -only-testing:FamiliarTests/SnapshotRenderTests CODE_SIGNING_ALLOWED=NO test
/// The PNGs are also attached to the test report.
@MainActor
final class SnapshotRenderTests: XCTestCase {
    func testRenderDemoScreens() throws {
        let outputDir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"]
        if let outputDir { try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true) }
        let defaults = UserDefaults(suiteName: "SnapshotRenderTests")!
        let screens: [(String, AnyView)] = [
            ("consent-card", AnyView(ConsentCardView(state: .listening,
                                                     question: Phrasebook.consentQuestion(userName: "Priya", name: "Marcus"),
                                                     onAnswer: { _ in }, onCancel: {}))),
            ("judge-stage", AnyView(JudgeStageView(tracks: SnapshotSamples.tracks, preview: nil, fps: 24,
                                                   route: "phone mic + glasses", micLevel: 0.6, consent: "idle",
                                                   cues: ["Normal mode.", "Three people.", "Marcus, ahead, close."]))),
            ("home", AnyView(HomeView().environmentObject(AppState(defaults: defaults)).environmentObject(AppCoordinator()))),
        ]
        for (name, view) in screens {
            let renderer = ImageRenderer(content: view.frame(width: 393, height: 852).preferredColorScheme(.dark))
            renderer.scale = 2
            guard let image = renderer.uiImage, let png = image.pngData() else {
                XCTFail("No image rendered for \(name)")
                continue
            }
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let outputDir {
                try png.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent("\(name).png"))
            }
        }
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
        ]
    }
}
