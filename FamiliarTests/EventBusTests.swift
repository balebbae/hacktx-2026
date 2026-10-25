import XCTest
@testable import Familiar

final class EventBusTests: XCTestCase {
    func testTwoSubscribersBothReceive() async {
        let bus = EventBus<Int>()
        let a = bus.subscribe(), b = bus.subscribe()
        XCTAssertEqual(bus.subscriberCount, 2)
        bus.publish(1); bus.publish(2); bus.finishAll()
        var ra: [Int] = [], rb: [Int] = []
        for await v in a { ra.append(v) }
        for await v in b { rb.append(v) }
        XCTAssertEqual(ra, [1, 2]); XCTAssertEqual(rb, [1, 2])
    }

    func testSlowSubscriberDropsUnderBufferingNewest() async {
        let bus = EventBus<Int>(defaultPolicy: .bufferingNewest(1))
        let s = bus.subscribe()
        for i in 0..<10 { bus.publish(i) }
        bus.finishAll()
        var got: [Int] = []
        for await v in s { got.append(v) }
        XCTAssertEqual(got, [9])
    }

    func testTerminatedSubscriberIsRemoved() async {
        let bus = EventBus<Int>()
        var stream: AsyncStream<Int>? = bus.subscribe()
        XCTAssertEqual(bus.subscriberCount, 1)
        var it = stream!.makeAsyncIterator()
        bus.publish(1)
        _ = await it.next()
        stream = nil
        it = AsyncStream<Int> { $0.finish() }.makeAsyncIterator()
        _ = await it.next()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertLessThanOrEqual(bus.subscriberCount, 1)
    }
}
