import XCTest
@testable import Familiar

final class TranscriberWindowTests: XCTestCase {
    func seg(_ text: String, _ start: TimeInterval, _ end: TimeInterval, speaker: SpeakerGuess = .other) -> TranscriptSegment {
        TranscriptSegment(text: text, start: start, end: end, isFinal: true, speaker: speaker)
    }

    func testWindowKeepsNinetySeconds() {
        let w = TranscriptWindow()
        w.append(seg("one", 5, 10))
        w.append(seg("two", 45, 50))
        w.append(seg("three", 115, 120))
        XCTAssertEqual(w.all.map(\.text), ["two", "three"])
        XCTAssertEqual(w.recent(seconds: 30, now: 120).map(\.text), ["three"])
        XCTAssertEqual(w.recent(seconds: 90, now: 120).map(\.text), ["two", "three"])
        XCTAssertEqual(w.recent(seconds: 500, now: 120).map(\.text), ["two", "three"], "never more than the window")
    }

    func testFallbackSkipsUnavailableCandidates() async throws {
        let fake = FakeTranscriber(text: "other: hi there", interval: 0.01)
        let t = FallbackTranscriber(candidates: [FailingTranscriber(), FailingTranscriber(error: TranscriberError.notAuthorized), fake])
        let stream = t.subscribe()
        try await t.start(audio: SilentAudioInput())
        XCTAssertEqual(t.activeName, "FakeTranscriber")
        XCTAssertEqual(t.startErrors.count, 2)
        var first: TranscriptSegment?
        for await s in stream { first = s; break }
        XCTAssertEqual(first?.text, "hi there")
        XCTAssertEqual(t.recentSegments(seconds: 90).count, 1)
        t.stop()
    }

    func testAllCandidatesFailingThrows() async {
        let t = FallbackTranscriber(candidates: [FailingTranscriber(), FailingTranscriber()])
        do {
            try await t.start(audio: SilentAudioInput())
            XCTFail("expected throw")
        } catch let e as TranscriberError {
            XCTAssertEqual(e, .unavailable("test"))
        } catch { XCTFail("\(error)") }
        XCTAssertEqual(t.activeName, "none")
    }

    func testSpeechFactoryFallsBackInSimulator() async throws {
        let t = SpeechFactory.makeTranscriber(promptForAuthorization: false)
        XCTAssertGreaterThanOrEqual(t.candidates.count, 2)
        XCTAssertTrue(t.candidates.last is FakeTranscriber)
        let started: Bool = await withTaskGroup(of: Bool.self) { group in
            group.addTask { (try? await t.start(audio: SilentAudioInput())) != nil }
            group.addTask { try? await Task.sleep(nanoseconds: 15_000_000_000); return false }
            let r = await group.next() ?? false
            group.cancelAll()
            return r
        }
        guard started else { throw XCTSkip("transcriber start did not settle in 15 s (asset download on this host?)") }
        print("[TranscriberWindowTests] active transcriber: \(t.activeName); errors: \(t.startErrors)")
        XCTAssertNotEqual(t.activeName, "none")
        t.stop()
    }

    func testAudioBuffersConvertChunk() {
        let chunk = AudioChunk(samples: [Float](repeating: 0.5, count: 320), sampleRate: 16_000, timestamp: 1)
        let buf = AudioBuffers.buffer(samples: chunk.samples, sampleRate: chunk.sampleRate)
        XCTAssertEqual(buf?.frameLength, 320)
        XCTAssertEqual(buf?.format.sampleRate, 16_000)
        var converter: AVAudioConverter?
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let converted = AudioBuffers.buffer(for: chunk, in: target, converter: &converter)
        XCTAssertEqual(Int(converted?.frameLength ?? 0), 960, accuracy: 10)
    }

    func testAudioChunkerResamples() {
        let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        let chunker = AudioChunker(inputFormat: input)!
        let buf = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4_800)!
        buf.frameLength = 4_800
        for ch in 0..<2 { for i in 0..<4_800 { buf.floatChannelData![ch][i] = 0.3 } }
        let first = chunker.chunk(buf, when: nil)
        let second = chunker.chunk(buf, when: nil)
        XCTAssertEqual(first?.sampleRate, 16_000)
        // The resampler keeps a little latency across calls (streaming tap), so the first chunk is slightly short.
        XCTAssertGreaterThan(first?.samples.count ?? 0, 1_200)
        XCTAssertLessThanOrEqual(first?.samples.count ?? 0, 1_600)
        XCTAssertEqual(second?.samples.count ?? 0, 1_600, accuracy: 300)
        XCTAssertEqual(first?.samples[800] ?? 0, 0.3, accuracy: 0.05)
    }
}

import AVFoundation
