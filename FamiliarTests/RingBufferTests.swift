import XCTest
@testable import Familiar

final class RingBufferTests: XCTestCase {
    func testWrapsAndKeepsNewest() {
        let ring = RingBuffer(seconds: 1, sampleRate: 100)
        XCTAssertEqual(ring.capacity, 100)
        XCTAssertNil(ring.timeRange)
        ring.write((0..<150).map(Float.init), at: 0)
        XCTAssertEqual(ring.count, 100)
        XCTAssertEqual(ring.all(), (50..<150).map(Float.init))
        let range = try! XCTUnwrap(ring.timeRange)
        XCTAssertEqual(range.lowerBound, 0.5, accuracy: 0.001)
        XCTAssertEqual(range.upperBound, 1.49, accuracy: 0.001, "time of the last sample")
    }

    func testSliceByHostTime() {
        let ring = RingBuffer(seconds: 1, sampleRate: 100)
        ring.write(AudioChunk(samples: (0..<60).map(Float.init), sampleRate: 100, timestamp: 10))
        ring.write(AudioChunk(samples: (60..<120).map(Float.init), sampleRate: 100, timestamp: 10.6))
        XCTAssertEqual(ring.slice(from: 10.5, to: 10.7), (50..<70).map(Float.init))
        XCTAssertEqual(ring.slice(from: 0, to: 10.3), (20..<30).map(Float.init), "clamped to what is still buffered")
        XCTAssertEqual(ring.slice(from: 11.5, to: 12), [])
    }

    func testThirtySecondDefault() {
        let ring = RingBuffer()
        XCTAssertEqual(ring.capacity, 30 * 16_000)
        XCTAssertEqual(ring.sampleRate, 16_000)
    }

    func testWAVExport() throws {
        let ring = RingBuffer(seconds: 1, sampleRate: 100)
        ring.write([Float](repeating: 0.5, count: 40), at: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ring-\(UUID().uuidString).wav")
        try ring.writeWAV(url: url)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 44 + 80)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        try? FileManager.default.removeItem(at: url)
    }
}
