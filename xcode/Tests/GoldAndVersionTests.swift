import XCTest

final class GoldAndVersionTests: XCTestCase {
    func testGoldParse() throws {
        let json = #"{"name":"Gold","price":2345.67,"symbol":"XAU"}"#
        let quote = try GoldAPI.parse(Data(json.utf8))
        XCTAssertEqual(quote.usdPerOunce, 2345.67, accuracy: 0.0001)
    }

    func testGoldParseRejectsNonPositiveOrMissingPrice() {
        XCTAssertThrowsError(try GoldAPI.parse(Data(#"{"price":0}"#.utf8)))
        XCTAssertThrowsError(try GoldAPI.parse(Data("{}".utf8)))
    }

    func testGoldFormatting() {
        XCTAssertEqual(Formatting.gold(2345.678), "2,345.68")
        XCTAssertEqual(Formatting.gold(99), "99.00")
        XCTAssertEqual(Formatting.gold(nil), Formatting.missing)
    }

    func testStale() {
        let now = Date()
        XCTAssertFalse(Formatting.isStale(now.addingTimeInterval(-59 * 60), now: now))
        XCTAssertTrue(Formatting.isStale(now.addingTimeInterval(-61 * 60), now: now))
        XCTAssertTrue(Formatting.isStale(nil, now: now))
    }

    func testIsNewer() {
        XCTAssertTrue(OSVersion.isNewer("27.0.2", than: "27.0.1"))
        XCTAssertFalse(OSVersion.isNewer("27.0.1", than: "27.0.1"))
        XCTAssertTrue(OSVersion.isNewer("27.1", than: "27.0.9"))
        XCTAssertFalse(OSVersion.isNewer("26.9", than: "27.0"))
        XCTAssertFalse(OSVersion.isNewer("27.0", than: "27.0.0"))
    }

    func testParseLatestTakesHighestRegardlessOfOrder() throws {
        let json = #"[{"cycle":"26","latest":"26.5"},{"cycle":"27","latest":"27.0.2"},{"cycle":"25","latest":"25.7.1"}]"#
        XCTAssertEqual(try OSVersion.parseLatest(Data(json.utf8)), "27.0.2")
    }

    func testParseLatestRejectsEmpty() {
        XCTAssertThrowsError(try OSVersion.parseLatest(Data("[]".utf8)))
        XCTAssertThrowsError(try OSVersion.parseLatest(Data(#"[{"cycle":"1"}]"#.utf8)))
    }

    func testStatus() {
        XCTAssertEqual(OSVersion.status(current: "27.0.1", latest: nil), .unknown)
        XCTAssertEqual(OSVersion.status(current: "27.0.1", latest: "27.0.1"), .upToDate)
        XCTAssertEqual(OSVersion.status(current: "27.0.1", latest: "27.0.3"), .updateAvailable("27.0.3"))
    }
}
