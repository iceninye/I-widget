import XCTest

final class RebootHintTests: XCTestCase {
    private let day: TimeInterval = 86_400

    func testUnknownUptimeHasNoHint() {
        XCTAssertEqual(RebootHint.level(uptime: nil), .none)
        XCTAssertEqual(RebootHint.level(uptime: -1), .none)
    }

    func testThresholds() {
        XCTAssertEqual(RebootHint.level(uptime: 0), .none)
        XCTAssertEqual(RebootHint.level(uptime: 5 * day - 1), .none)
        XCTAssertEqual(RebootHint.level(uptime: 5 * day), .soon)
        XCTAssertEqual(RebootHint.level(uptime: 7 * day - 1), .soon)
        XCTAssertEqual(RebootHint.level(uptime: 7 * day), .due)
        XCTAssertEqual(RebootHint.level(uptime: 30 * day), .due)
    }

    func testSuffix() {
        XCTAssertEqual(RebootHint.none.suffix, "")
        XCTAssertEqual(RebootHint.soon.suffix, " · 快要重啟")
        XCTAssertEqual(RebootHint.due.suffix, " · 建議重啟")
    }
}
