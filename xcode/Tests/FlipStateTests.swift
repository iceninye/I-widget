import XCTest

final class FlipStateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testToggleAndExpire() {
        var state = FlipState()
        state.toggle("battery", now: start)
        XCTAssertTrue(state.isFlipped("battery", at: start.addingTimeInterval(10)))
        XCTAssertFalse(state.isFlipped("gold", at: start))
        XCTAssertFalse(state.isFlipped("battery", at: start.addingTimeInterval(FlipState.duration)))
        XCTAssertEqual(state.expiries(after: start), [start.addingTimeInterval(FlipState.duration)])

        state.toggle("battery", now: start.addingTimeInterval(20))
        XCTAssertFalse(state.isFlipped("battery", at: start.addingTimeInterval(21)))
    }

    func testExpiredFlipIsPrunedOnNextToggle() {
        var state = FlipState()
        state.toggle("gold", now: start)
        state.toggle("ios", now: start.addingTimeInterval(200))
        XCTAssertEqual(Set(state.flipped.keys), ["ios"])
        // 過咗期再撳同一格 = 重新反轉，唔係反返轉頭
        state.toggle("ios", now: start.addingTimeInterval(400))
        XCTAssertTrue(state.isFlipped("ios", at: start.addingTimeInterval(401)))
    }
}
