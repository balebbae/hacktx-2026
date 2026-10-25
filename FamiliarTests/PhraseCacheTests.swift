import XCTest
@testable import Familiar

final class PhraseCacheTests: XCTestCase {
    var dir: URL!
    var cache: PhraseCache!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tts-tests-\(UUID().uuidString)")
        cache = PhraseCache(directory: dir)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func testKeyIsStableSHA256() {
        let k1 = PhraseCache.key(voiceID: "v", model: "m", text: "Marcus, ahead, close.")
        let k2 = PhraseCache.key(voiceID: "v", model: "m", text: "Marcus, ahead, close.")
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 64)
        XCTAssertTrue(k1.allSatisfy { $0.isHexDigit })
        XCTAssertNotEqual(k1, PhraseCache.key(voiceID: "v", model: "m", text: "Marcus, ahead, far."))
        XCTAssertNotEqual(k1, PhraseCache.key(voiceID: "other", model: "m", text: "Marcus, ahead, close."))
        XCTAssertEqual(cache.url(voiceID: "v", model: "m", text: "x").pathExtension, "pcm")
    }

    func testStoreAndLoadRoundTrip() {
        XCTAssertFalse(cache.has(voiceID: "v", model: "m", text: "hi"))
        XCTAssertNil(cache.samples(voiceID: "v", model: "m", text: "hi"))
        let samples: [Float] = [0, 0.5, -0.5, 1, -1, 0.25]
        cache.store(samples: samples, voiceID: "v", model: "m", text: "hi")
        XCTAssertTrue(cache.has(voiceID: "v", model: "m", text: "hi"))
        let back = try! XCTUnwrap(cache.samples(voiceID: "v", model: "m", text: "hi"))
        XCTAssertEqual(back.count, samples.count)
        for (a, b) in zip(back, samples) { XCTAssertEqual(a, b, accuracy: 0.0001) }
        XCTAssertEqual(cache.files().count, 1)
        cache.clear()
        XCTAssertEqual(cache.files().count, 0)
    }

    func testEmptyFileIsNotAHit() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cache.url(voiceID: "v", model: "m", text: "empty").path, contents: Data())
        XCTAssertFalse(cache.has(voiceID: "v", model: "m", text: "empty"))
    }

    func testPCM16EncodeDecode() {
        let data = PCM16.encode([0, 1, -1, 0.5])
        XCTAssertEqual(data.count, 8)
        XCTAssertEqual([UInt8](data.prefix(4)), [0x00, 0x00, 0xFF, 0x7F])
        let decoded = PCM16.decode(data)
        XCTAssertEqual(decoded.count, 4)
        XCTAssertEqual(decoded[1], 1, accuracy: 0.0001)
        XCTAssertEqual(decoded[2], -1, accuracy: 0.0001)
        XCTAssertEqual(decoded[3], 0.5, accuracy: 0.0001)
        XCTAssertEqual(PCM16.decode(Data([0x01])).count, 0, "odd trailing byte ignored")
    }
}
