import XCTest
@testable import Familiar

final class LoudnessSplitTests: XCTestCase {
    func chunk(amplitude: Float, seconds: TimeInterval, at t: TimeInterval, rate: Double = 16_000) -> AudioChunk {
        let n = Int(seconds * rate)
        let samples = (0..<n).map { i in amplitude * sin(Float(i) * 2 * .pi * 220 / Float(rate)) }
        return AudioChunk(samples: samples, sampleRate: rate, timestamp: t)
    }

    func testSpeechDetectionLoudnessGuessAndHangover() {
        let vad = LoudnessSplit()
        vad.process(chunk(amplitude: 0.0005, seconds: 1.0, at: 0))
        XCTAssertFalse(vad.current.isSpeech)
        XCTAssertEqual(vad.current.guess, .none)

        vad.process(chunk(amplitude: 0.3, seconds: 0.3, at: 1.0))
        XCTAssertTrue(vad.current.isSpeech)
        XCTAssertEqual(vad.current.guess, .user, "loud = the wearer")

        vad.process(chunk(amplitude: 0.03, seconds: 0.3, at: 1.3))
        XCTAssertTrue(vad.current.isSpeech)
        XCTAssertEqual(vad.current.guess, .other, "quieter than 0.6 × user RMS = someone else")

        vad.process(chunk(amplitude: 0.0005, seconds: 0.2, at: 1.6))
        XCTAssertTrue(vad.current.isSpeech, "250 ms hangover keeps speech on")
        vad.process(chunk(amplitude: 0.0005, seconds: 0.5, at: 1.8))
        XCTAssertFalse(vad.current.isSpeech)
        XCTAssertEqual(vad.current.guess, .none)

        XCTAssertEqual(vad.guess(at: 1.15), .user)
        XCTAssertEqual(vad.guess(at: 1.45), .other)
    }

    func testPublishesOnlyChanges() async {
        let vad = LoudnessSplit()
        let stream = vad.subscribe()
        vad.process(chunk(amplitude: 0.0005, seconds: 0.5, at: 0))
        vad.process(chunk(amplitude: 0.3, seconds: 0.2, at: 0.5))
        vad.process(chunk(amplitude: 0.0005, seconds: 0.6, at: 0.7))
        var got: [(isSpeech: Bool, guess: SpeakerGuess, t: TimeInterval)] = []
        for await s in stream { got.append(s); if got.count == 2 { break } }
        XCTAssertEqual(got[0].isSpeech, true)
        XCTAssertEqual(got[0].guess, .user)
        XCTAssertEqual(got[0].t, 0.5, accuracy: 0.03)
        XCTAssertEqual(got[1].isSpeech, false)
        XCTAssertEqual(got[1].t, 0.95, accuracy: 0.05)
    }

    func testCalibrationMovesThreshold() {
        let vad = LoudnessSplit()
        XCTAssertFalse(vad.isCalibrated)
        vad.calibrateUser(with: chunk(amplitude: 0.5, seconds: 0.5, at: 0).samples)
        XCTAssertTrue(vad.isCalibrated)
        XCTAssertEqual(vad.userRMS, 0.35, accuracy: 0.02)
        vad.process(chunk(amplitude: 0.0005, seconds: 1.0, at: 0))
        vad.process(chunk(amplitude: 0.1, seconds: 0.3, at: 1.0))
        XCTAssertEqual(vad.current.guess, .other, "0.1 amplitude is quiet for a wearer calibrated at 0.5")
    }

    func testExternalDetectorOverridesEnergy() {
        let vad = LoudnessSplit()
        vad.process(chunk(amplitude: 0.0005, seconds: 1.0, at: 0))
        vad.noteExternalSpeech(false, at: 1.0)
        vad.process(chunk(amplitude: 0.3, seconds: 0.3, at: 1.0))
        XCTAssertFalse(vad.current.isSpeech, "SpeechDetector said no speech")
    }

    func testFactoryAttachesToInput() async {
        let input = EngineAudioInput(route: { .phoneOnly })
        let vad = AudioFactory.makeVoiceActivity(audio: input)
        let stream = vad.subscribe()
        try? await Task.sleep(nanoseconds: 50_000_000)
        input.publish(chunk(amplitude: 0.0005, seconds: 0.5, at: 0))
        input.publish(chunk(amplitude: 0.3, seconds: 0.2, at: 0.5))
        var first: (isSpeech: Bool, guess: SpeakerGuess, t: TimeInterval)?
        for await s in stream { first = s; break }
        XCTAssertEqual(first?.isSpeech, true)
        vad.stop()
    }
}
