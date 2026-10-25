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

    func testWallAlertsWhileWalkingRepeatOnlyWhileClosingInAndRearmWhenClear() {
        var p = NarrationPolicy()
        func wall(_ m: Double, at t: TimeInterval, _ what: String = "wall") -> SceneReading {
            var r = reading(.blocked, what: what, meters: m); r.at = t; return r
        }
        XCTAssertNotEqual(p.utterances(for: wall(3.4, at: 0), mode: .quiet, now: 0, inConversation: false, moving: false).first?.category, "hazard", "standing still: no alert")
        let first = p.utterances(for: wall(3.4, at: 0), mode: .normal, now: 0, inConversation: false, moving: true)
        XCTAssertEqual(first.map(\.text), ["Wall ahead, 3 meters."])
        XCTAssertEqual(first.first?.priority, 0)
        XCTAssertNotEqual(p.utterances(for: wall(3.2, at: 5), mode: .normal, now: 5, inConversation: false).first?.category, "hazard", "not closer")
        XCTAssertNotEqual(p.utterances(for: wall(2.2, at: 2), mode: .normal, now: 2, inConversation: false).first?.category, "hazard", "closer but within 5 s")
        XCTAssertNotEqual(p.utterances(for: wall(3.0, at: 4), mode: .normal, now: 6, inConversation: true).first?.category, "hazard", "face to face: only close obstacles")
        XCTAssertEqual(p.utterances(for: wall(3.0, at: 4), mode: .normal, now: 6, inConversation: false).map(\.text), ["Wall ahead, 2 meters."], "3 m aged by 2 s of walking (at most 1 m)")
        XCTAssertEqual(p.utterances(for: wall(1.0, at: 20), mode: .quiet, now: 20, inConversation: true).map(\.text), ["Wall ahead, close."], "once more when it gets close, quiet or not")
        _ = p.utterances(for: reading(), mode: .quiet, now: 21, inConversation: false)
        _ = p.utterances(for: reading(), mode: .quiet, now: 24.5, inConversation: false)
        XCTAssertNotEqual(p.utterances(for: wall(1.0, at: 25, "chair"), mode: .normal, now: 25, inConversation: false).first?.category, "hazard", "3.5 s clear is not enough to re-arm")
        _ = p.utterances(for: reading(), mode: .quiet, now: 26, inConversation: false)
        _ = p.utterances(for: reading(), mode: .quiet, now: 31.5, inConversation: false)
        XCTAssertEqual(p.utterances(for: wall(1.8, at: 32, "chair"), mode: .normal, now: 32, inConversation: false).map(\.text), ["Chair ahead, 2 meters."], "re-armed after 5 s clear")
    }

    func testTheSameObstacleUnderANewNameIsNotRepeated() {
        // Device log, 06:16:30–06:17:00: one couch read as couch, sofa, chair, couch while sitting still → 9 alerts.
        var p = NarrationPolicy()
        var said: [String] = []
        for (i, (what, m)) in [("couch", 1.0), ("sofa", 1.0), ("couch", 0.8), ("chair", 2.5), ("couch", 0.8), ("wall", 2.0), ("wall", 1.0), ("sofa", 1.0)].enumerated() {
            var r = reading(.blocked, what: what, meters: m); r.at = Double(i) * 2
            said += p.utterances(for: r, mode: .normal, now: r.at, inConversation: false).map(\.text)
        }
        XCTAssertEqual(said, ["Couch ahead, close."])
    }

    func testThePersonYouAreTalkingToIsNotAnObstacle() {
        var p = NarrationPolicy()
        XCTAssertEqual(p.utterances(for: reading(.blocked, what: "person", meters: 1), mode: .normal, now: 0, inConversation: true), [])
        XCTAssertEqual(p.utterances(for: reading(.blocked, what: "person", meters: 1), mode: .normal, now: 1, inConversation: false).map(\.text), ["Person ahead, close."])
    }

    func testANewObstacleBehindTheOldOneIsAnnounced() {
        var p = NarrationPolicy()
        func r(_ what: String, _ m: Double, _ t: TimeInterval) -> SceneReading { var x = reading(.blocked, what: what, meters: m); x.at = t; return x }
        XCTAssertEqual(p.utterances(for: r("laptop", 0.4, 0), mode: .normal, now: 0, inConversation: false).map(\.text), ["Laptop ahead, close."])
        XCTAssertEqual(p.utterances(for: r("wall", 3.5, 4), mode: .normal, now: 4, inConversation: false).map(\.text), ["Wall ahead, 4 meters."], "the session log case: the wall was never announced")
        XCTAssertEqual(p.utterances(for: r("wall", 1.2, 10), mode: .normal, now: 10, inConversation: false).map(\.text), ["Wall ahead, close."])
    }

    func testFarCautionIsNotAnAlert() {
        var p = NarrationPolicy()
        XCTAssertNotEqual(p.utterances(for: reading(.caution, what: "table", meters: 6), mode: .quiet, now: 0, inConversation: false).first?.category, "hazard")
    }

    func testHazardsOncePerCooldown() {
        var p = NarrationPolicy()
        let r = reading(hazards: [.init(name: "stairs down", x: 0.5, meters: 3)])
        let bag = reading(hazards: [.init(name: "bag", x: 0.5, meters: 2)])
        XCTAssertEqual(p.utterances(for: r, mode: .quiet, now: 0, inConversation: false).map(\.text), ["Stairs down, 12 o'clock, 3 meters."])
        XCTAssertEqual(p.utterances(for: r, mode: .quiet, now: 30, inConversation: false), [])
        XCTAssertEqual(p.utterances(for: bag, mode: .quiet, now: 5, inConversation: false), [], "any two hazards 10 s apart")
        XCTAssertEqual(p.utterances(for: bag, mode: .quiet, now: 12, inConversation: false).count, 1)
        XCTAssertEqual(p.utterances(for: r, mode: .quiet, now: 61, inConversation: false).count, 1)
    }

    func testGistOnlyInChattyModeWhenChanged() {
        var p = NarrationPolicy()
        XCTAssertEqual(p.utterances(for: reading(), mode: .quiet, now: 0, inConversation: false), [], "quiet mode never narrates")
        XCTAssertEqual(p.utterances(for: reading(), mode: .normal, now: 1, inConversation: false), [], "normal mode: only when asked")
        XCTAssertEqual(p.utterances(for: reading(), mode: .normal, now: 2, inConversation: false, moving: false), [])
        let first = p.utterances(for: reading(), mode: .chatty, now: 3, inConversation: false, moving: false)
        XCTAssertEqual(first.map(\.text), ["Hallway, door at 1 o'clock."])
        XCTAssertEqual(first.first?.priority, 2)
        XCTAssertEqual(p.utterances(for: reading(summary: "Long hallway ahead."), mode: .chatty, now: 30, inConversation: false), [], "same scene: no gist")
        let kitchen = reading(place: "kitchen", objects: ["table", "fridge"], summary: "Kitchen, table at 12 o'clock.")
        XCTAssertEqual(p.utterances(for: kitchen, mode: .chatty, now: 8, inConversation: false), [], "too soon")
        XCTAssertEqual(p.utterances(for: kitchen, mode: .chatty, now: 12, inConversation: true), [])
        XCTAssertEqual(p.utterances(for: kitchen, mode: .chatty, now: 12, inConversation: false).map(\.text), ["Kitchen, table at 12 o'clock."])
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

    func testRepliesOnlyAfterAQuestionOrAButtonPressNeverToRoomChatter() async {
        await brain.ask("what's on the table")
        now += 3
        await brain.hear(TranscriptSegment(text: "is there a door", start: now, end: now, isFinal: true, speaker: .user))
        XCTAssertEqual(vision.prompts.count, 1, "a plain answer opens nothing: in a busy room the next sentence may be anyone's")

        vision.reply = ["say": "Which one, the door or the window?", "action": "none", "name": NSNull(), "mode": NSNull()]
        await brain.ask("what's that over there")
        now += 2
        await brain.hear(TranscriptSegment(text: "the door", start: now, end: now, isFinal: true, speaker: .other))
        XCTAssertEqual(vision.prompts.count, 3, "Poyo asked, so the next sentence is the reply, whatever the voice split says")
        XCTAssertTrue(vision.prompts[2].hasSuffix("[to you] the door"))
        XCTAssertTrue(vision.prompts[2].contains("You last said: Which one, the door or the window?"))
        await brain.hear(TranscriptSegment(text: "and the window", start: now, end: now, isFinal: true, speaker: .user))
        XCTAssertEqual(vision.prompts.count, 4, "it asked again, so one more")

        vision.reply = ["say": "A door at 1 o'clock.", "action": "none", "name": NSNull(), "mode": NSNull()]
        brain.listenNext()                                   // volume button
        await brain.hear(TranscriptSegment(text: "is there a sign", start: now, end: now, isFinal: true, speaker: .other))
        XCTAssertEqual(vision.prompts.count, 5, "push-to-talk takes the next sentence")
        await brain.hear(TranscriptSegment(text: "is there a sign", start: now, end: now, isFinal: true, speaker: .other))
        XCTAssertEqual(vision.prompts.count, 5, "and only that one")
    }

    func testRenameWithoutANameAsksForIt() async {
        var renamed: [String] = []
        brain.rename = { renamed.append($0); return Phrasebook.renamed($0) }
        await brain.ask("can you update his name")
        XCTAssertEqual(speaker.texts, [Phrasebook.whatName])
        XCTAssertEqual(vision.prompts.count, 0)
        now += 2
        await brain.hear(TranscriptSegment(text: "His name is Jagadeep.", start: now - 1, end: now, isFinal: true, speaker: .other))
        XCTAssertEqual(renamed, ["Jagadeep"])
        XCTAssertEqual(speaker.texts.last, "Updated. That's Jagadeep now.")
        XCTAssertEqual(PoyoBrain.spokenName(in: "It's Jagadeep"), "Jagadeep")
        XCTAssertEqual(PoyoBrain.spokenName(in: "um his name is Jaga Deep please"), "Jaga Deep")
        XCTAssertNil(PoyoBrain.spokenName(in: "no"))
        XCTAssertTrue(PoyoBrain.isRenameRequest("Poyo can you change his contact"))
        XCTAssertFalse(PoyoBrain.isRenameRequest("what is his name"))
    }

    func testRenameRequestsAreUnderstoodOnThePhone() async {
        XCTAssertEqual(PoyoBrain.renameTarget(in: "can you update their contact to be Anish instead of someone I know"), "Anish")
        XCTAssertEqual(PoyoBrain.renameTarget(in: "Change his name to Anish Patel."), "Anish Patel")
        XCTAssertEqual(PoyoBrain.renameTarget(in: "their name is actually Anish"), "Anish")
        XCTAssertEqual(PoyoBrain.renameTarget(in: "save them as Anish instead"), "Anish")
        XCTAssertNil(PoyoBrain.renameTarget(in: "call Marcus"))
        XCTAssertNil(PoyoBrain.renameTarget(in: "change to quiet mode"))
        XCTAssertNil(PoyoBrain.renameTarget(in: "what's on the table"))
        var renamed: [String] = []
        brain.rename = { renamed.append($0); return Phrasebook.renamed($0) }
        await brain.ask("update their contact to be Anish instead of someone I know")
        XCTAssertEqual(renamed, ["Anish"])
        XCTAssertEqual(vision.prompts.count, 0, "no model call")
        XCTAssertEqual(speaker.texts, ["Updated. That's Anish now."])
        vision.reply = ["say": "", "action": "rename", "name": "Priya", "mode": NSNull()]
        await brain.ask("she goes by Priya")
        XCTAssertEqual(renamed, ["Anish", "Priya"], "the model can ask for a rename too")
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
