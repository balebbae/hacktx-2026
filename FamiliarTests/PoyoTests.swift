import XCTest
import CoreGraphics
@testable import Familiar

/// Narration, scene decoding, sanitizer, question filter, redaction and the vision brain (with a fake model).
final class NarrationPolicyTests: XCTestCase {
    func reading(_ path: SceneReading.PathStatus = .clear, what: String? = nil, meters: Double? = nil, hazards: [SceneReading.Item] = [],
                 place: String? = "hallway", objects: [String] = ["door"], summary: String = "Hallway, door at 1 o'clock.") -> SceneReading {
        SceneReading(path: path, pathWhat: what, pathX: 0.5, pathMeters: meters, hazards: hazards, place: place,
                     objects: objects.map { .init(name: $0, x: 0.8, meters: 4) }, summary: summary, hFOV: 53)
    }

    func testWallAlertsAtOnceRepeatsWhileInTheWayAndRearmsWhenClear() {
        var p = NarrationPolicy()
        let wall = reading(.blocked, what: "wall", meters: 1.8)
        let first = p.utterances(for: wall, mode: .normal, now: 0, inConversation: false)
        XCTAssertEqual(first.map(\.text), ["Wall ahead, 2 meters."])
        XCTAssertEqual(first.first?.priority, 0)
        XCTAssertNotEqual(p.utterances(for: wall, mode: .normal, now: 3, inConversation: false).first?.category, "hazard", "no repeat within 8 s")
        XCTAssertEqual(p.utterances(for: wall, mode: .normal, now: 9, inConversation: true).map(\.text), ["Wall ahead, 2 meters."], "still in the way; even mid-conversation")
        _ = p.utterances(for: reading(), mode: .quiet, now: 10, inConversation: false)
        _ = p.utterances(for: reading(), mode: .quiet, now: 13.5, inConversation: false)
        XCTAssertEqual(p.utterances(for: wall, mode: .quiet, now: 14, inConversation: false).map(\.text), ["Wall ahead, 2 meters."], "re-armed after 3 s clear")
    }

    func testFarCautionIsNotAnAlert() {
        var p = NarrationPolicy()
        XCTAssertNotEqual(p.utterances(for: reading(.caution, what: "table", meters: 6), mode: .quiet, now: 0, inConversation: false).first?.category, "hazard")
    }

    func testHazardsOncePerCooldown() {
        var p = NarrationPolicy()
        let r = reading(hazards: [.init(name: "stairs down", x: 0.5, meters: 3)])
        XCTAssertEqual(p.utterances(for: r, mode: .quiet, now: 0, inConversation: false).map(\.text), ["Stairs down, 12 o'clock, 3 meters."])
        XCTAssertEqual(p.utterances(for: r, mode: .quiet, now: 5, inConversation: false), [])
        XCTAssertEqual(p.utterances(for: r, mode: .quiet, now: 11, inConversation: false).count, 1)
    }

    func testGistOnlyWhenChangedAndPacedByMode() {
        var p = NarrationPolicy()
        XCTAssertEqual(p.utterances(for: reading(), mode: .quiet, now: 0, inConversation: false), [], "quiet mode never narrates")
        let first = p.utterances(for: reading(), mode: .normal, now: 1, inConversation: false)
        XCTAssertEqual(first.map(\.text), ["Hallway, door at 1 o'clock."])
        XCTAssertEqual(first.first?.priority, 2)
        XCTAssertEqual(p.utterances(for: reading(summary: "Long hallway ahead."), mode: .normal, now: 30, inConversation: false), [], "same scene: no gist")
        let kitchen = reading(place: "kitchen", objects: ["table", "fridge"], summary: "Kitchen, table at 12 o'clock.")
        XCTAssertEqual(p.utterances(for: kitchen, mode: .normal, now: 10, inConversation: false), [], "too soon in normal mode")
        XCTAssertEqual(p.utterances(for: kitchen, mode: .normal, now: 10, inConversation: true), [])
        XCTAssertEqual(p.utterances(for: kitchen, mode: .normal, now: 22, inConversation: false).map(\.text), ["Kitchen, table at 12 o'clock."])
        let office = reading(place: "office", objects: ["desk"], summary: "Office, desk at 11 o'clock.")
        XCTAssertEqual(p.utterances(for: office, mode: .chatty, now: 31, inConversation: false).count, 1, "chatty: 8 s")
    }

    func testGistNeverDescribesPeople() {
        var p = NarrationPolicy()
        XCTAssertEqual(p.utterances(for: reading(summary: "A man in a red shirt is waving."), mode: .chatty, now: 0, inConversation: false), [])
    }
}

final class SceneReadingTests: XCTestCase {
    func testDecodesModelJSONAndMapsXToTrueClock() throws {
        let json: [String: Any] = [
            "path": ["status": "blocked", "what": "glass door", "x": 0.95, "meters": 1.2],
            "hazards": [["name": "step", "x": 0.05, "meters": NSNull()]],
            "place": "lobby", "objects": [["name": "elevator", "x": 0.5, "meters": 6]],
            "signs": ["EXIT"], "summary": "Lobby, elevator at 12 o'clock.",
        ]
        let r = try XCTUnwrap(SceneReading(json: json, at: 5, hFOV: 53))
        XCTAssertEqual(r.path, .blocked)
        XCTAssertEqual(r.pathWhat, "glass door")
        XCTAssertEqual(r.bearing(r.pathX).clock, 1)
        XCTAssertEqual(r.hazards.first?.meters, nil)
        XCTAssertEqual(r.bearing(r.hazards[0].x).clock, 11)
        XCTAssertEqual(r.signs, ["EXIT"])
        let line = WorldModel.contextLine(tracks: [], reading: r, now: 7)
        XCTAssertTrue(line.contains("Path blocked: glass door at 1 o'clock, 1 meter."), line)
        XCTAssertTrue(line.contains("Objects: elevator 12 o'clock 6 meters."), line)
        XCTAssertTrue(line.contains("Signs: EXIT."), line)
        XCTAssertTrue(line.hasPrefix("Visible now: no one."), line)
    }

    func testMissingPathIsRejected() {
        XCTAssertNil(SceneReading(json: ["summary": "x"], at: 0, hFOV: 53))
    }
}

final class SpeechSanitizerTests: XCTestCase {
    func testCleansModelLines() {
        XCTAssertNil(SpeechSanitizer.clean("SKIP"))
        XCTAssertNil(SpeechSanitizer.clean("  "))
        XCTAssertEqual(SpeechSanitizer.clean("Poyo, the door is at 1 o'clock"), "The door is at 1 o'clock.")
        XCTAssertEqual(SpeechSanitizer.clean("Door at 1 o'clock. A woman with blonde hair is next to it."), "Door at 1 o'clock.")
        XCTAssertNil(SpeechSanitizer.clean("Their face is blacked out."))
        XCTAssertEqual(SpeechSanitizer.clean("Marcus is at 12 o'clock and 2 other people are here."), "Marcus is at 12 o'clock and 2 other people are here.")
        XCTAssertEqual(SpeechSanitizer.clean("one two three four five six", maxWords: 3), "One two three.")
        XCTAssertEqual(SpeechSanitizer.clean("**Chair** ahead"), "Chair ahead.")
    }

    func testQuestionFilter() {
        for q in ["what's on the table", "Is there a door nearby", "where's the exit?", "can you read that sign", "how many chairs are there", "describe the room", "anything in my way"] {
            XCTAssertTrue(QuestionFilter.isRequestLike(q), q)
        }
        for s in ["I think so", "nice to meet you", "yeah", "the demo went great", "ok"] {
            XCTAssertFalse(QuestionFilter.isRequestLike(s), s)
        }
    }
}

final class FrameRedactorTests: XCTestCase {
    private func whiteImage(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, _ x: Int, _ yTop: Int) -> UInt8 {
        var px = [UInt8](repeating: 0, count: image.width * image.height)
        let ctx = CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return px[yTop * image.width + x]          // bitmap memory is top row first
    }

    func testBoxesAreBlackedOutWithMarginInTopLeftCoordinates() throws {
        let image = whiteImage(100, 200)
        let out = try XCTUnwrap(FrameRedactor.redacted(image, boxes: [CGRect(x: 0.4, y: 0.1, width: 0.2, height: 0.1)], margin: 0.35))
        XCTAssertEqual(pixel(out, 50, 30), 0, "box centre (top part of the image) is black")
        XCTAssertEqual(pixel(out, 37, 30), 0, "margin is black too")
        XCTAssertEqual(pixel(out, 50, 150), 255, "the rest is untouched")
        XCTAssertEqual(pixel(out, 5, 30), 255)
        XCTAssertNotNil(FrameRedactor.jpeg(out))
    }

    func testThumbnailDifference() {
        let a = FrameRedactor.thumbnail(whiteImage(64, 64))
        XCTAssertEqual(a.count, 256)
        XCTAssertEqual(FrameRedactor.difference(a, a), 0)
        XCTAssertEqual(FrameRedactor.difference(a, []), 1)
    }
}

// MARK: - Brain

final class FakeVision: VisionLLM, @unchecked Sendable {
    var isConfigured = true
    var reply: [String: Any] = ["say": "A door at 1 o'clock, about 3 meters.", "action": "none", "name": NSNull(), "mode": NSNull()]
    private(set) var prompts: [String] = []
    private(set) var images: [Data?] = []
    func complete(system: String, text: String, imageJPEG: Data?, schemaName: String, schema: [String: Any], maxTokens: Int, cacheKey: String, timeout: TimeInterval) async throws -> [String: Any] {
        prompts.append(text); images.append(imageJPEG)
        return reply
    }
}

@MainActor
final class PoyoBrainTests: XCTestCase {
    var perception: FakePerception!
    var speaker: LogSpeaker!
    var gate: CueGate!
    var flow: FakeConsentFlow!
    var vision: FakeVision!
    var transcriber: FakeTranscriber!
    var router: CommandRouter!
    var brain: PoyoBrain!
    var scene: CloudScene!
    var now: TimeInterval = 100
    let marcusID = UUID()

    override func setUp() async throws {
        perception = FakePerception(); speaker = LogSpeaker(simulateDuration: false); gate = CueGate(); flow = FakeConsentFlow(); vision = FakeVision()
        transcriber = FakeTranscriber(text: "")
        let store = InMemoryPeopleStore()
        router = CommandRouter(perception: perception, speaker: speaker, cueGate: gate, consentFlow: flow, peopleStore: store, contacts: NoopContactsBridge(), setMode: { _ in }, setMuted: { _ in })
        scene = CloudScene(client: vision)
        brain = PoyoBrain(vision: vision, scene: scene, perception: perception, transcriber: transcriber, speaker: speaker, cueGate: gate, router: router,
                          userName: { "Caleb" }, knownNames: { ["Marcus"] })
        brain.clock = { [unowned self] in now }
        router.askAssistant = { [weak brain] q in await brain?.ask(q) }
    }

    func testQuestionGoesToTheModelWithContextAndIsSpokenAtOnce() async {
        perception.tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.9))]
        await brain.ask("is there a door")
        XCTAssertEqual(vision.prompts.count, 1)
        XCTAssertTrue(vision.prompts[0].contains("Visible now: Marcus 12 o'clock close"), vision.prompts[0])
        XCTAssertTrue(vision.prompts[0].contains("People you may name: Marcus"))
        XCTAssertTrue(vision.prompts[0].hasSuffix("[to you] is there a door"))
        XCTAssertNil(vision.images[0], "no frame yet: nothing uploaded")
        XCTAssertEqual(speaker.texts, ["A door at 1 o'clock, about 3 meters."])
        XCTAssertEqual(speaker.entries.last?.utterance.priority, 0)
    }

    func testBuiltInCommandsStayOnThePhoneButSurroundingsUseTheModel() async {
        await brain.ask("who's here")
        XCTAssertEqual(vision.prompts.count, 0)
        XCTAssertEqual(speaker.texts, [Phrasebook.nobody])
        await router.handle(.describeSurroundings)
        XCTAssertEqual(vision.prompts.count, 1, "what's around me goes to the live view")
    }

    func testWhatsAroundMeAnswersAtOnceFromAFreshReading() async {
        perception.tracks = [FakePerception.track(1, identity: .known(personID: marcusID, name: "Marcus", score: 0.9))]
        scene.ingest(SceneReading(summary: "Office, chair at 12 o'clock, about 2 meters.", at: now - 1))
        await brain.ask("what's in front of me")
        XCTAssertEqual(vision.prompts.count, 0, "no model call")
        XCTAssertEqual(speaker.texts, ["Marcus, 12 o'clock, close. No one else. Office, chair at 12 o'clock, about 2 meters."])
        now += 10
        await brain.ask("what's in front of me")
        XCTAssertEqual(vision.prompts.count, 1, "stale reading: ask the model")
    }

    func testActionsRunThroughTheRouterAndRememberStartsConsent() async {
        vision.reply = ["say": "Okay.", "action": "remember", "name": NSNull(), "mode": NSNull()]
        await brain.ask("could you keep this person in my contacts")
        await waitUntil { self.flow.begins.count == 1 }
        XCTAssertEqual(flow.begins, [false])
        XCTAssertFalse(speaker.texts.contains("Okay."), "the model never confirms consent itself")
    }

    func testFollowUpWindowAndOverheardFilter() async {
        await brain.ask("what's on the table")
        XCTAssertEqual(vision.prompts.count, 1)
        now += 3
        await brain.hear(TranscriptSegment(text: "and to my left", start: now, end: now, isFinal: true, speaker: .user))
        XCTAssertEqual(vision.prompts.count, 2, "follow-up without the wake word")
        XCTAssertTrue(vision.prompts[1].hasSuffix("[to you] and to my left"))
        now += 30
        await brain.hear(TranscriptSegment(text: "yeah that sounds good", start: now, end: now, isFinal: true, speaker: .user))
        XCTAssertEqual(vision.prompts.count, 2, "small talk is not sent")
        await brain.hear(TranscriptSegment(text: "nice to meet you", start: now, end: now, isFinal: true, speaker: .other))
        await brain.hear(TranscriptSegment(text: "where is the exit?", start: now, end: now, isFinal: true, speaker: .user))
        XCTAssertEqual(vision.prompts.count, 2, "someone else just spoke: it is their conversation")
        now += 11
        vision.reply = ["say": "SKIP", "action": "none", "name": NSNull(), "mode": NSNull()]
        let before = speaker.texts.count
        await brain.hear(TranscriptSegment(text: "where is the exit?", start: now, end: now, isFinal: true, speaker: .user))
        XCTAssertEqual(vision.prompts.count, 3)
        XCTAssertTrue(vision.prompts[2].hasSuffix("[overheard] where is the exit?"))
        XCTAssertEqual(speaker.texts.count, before, "SKIP is silent")
    }

    func testNothingDuringConsent() async {
        brain.consentActive = { true }
        await brain.ask("what's on the table")
        XCTAssertEqual(vision.prompts.count, 0)
        XCTAssertEqual(speaker.texts, [])
    }

    private func waitUntil(_ timeout: TimeInterval = 1, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline { try? await Task.sleep(for: .seconds(0.01)) }
    }
}
