import XCTest

final class BatteryStyleTests: XCTestCase {
    func testSymbolFollowsLevel() {
        let symbols = [1.0, 0.7, 0.5, 0.2, 0.05].map { BatteryStyle.symbol(level: $0, charging: false) }
        XCTAssertEqual(symbols, [
            "battery.100percent", "battery.75percent", "battery.50percent",
            "battery.25percent", "battery.0percent",
        ])
    }

    func testChargingUsesBolt() {
        XCTAssertEqual(BatteryStyle.symbol(level: 0.3, charging: true), "battery.100percent.bolt")
    }

    func testUnknownLevel() {
        XCTAssertEqual(BatteryStyle.symbol(level: nil, charging: false), "battery.0percent")
        XCTAssertEqual(BatteryStyle.tone(level: nil, charging: false), .unknown)
    }

    func testTone() {
        XCTAssertEqual(BatteryStyle.tone(level: 0.1, charging: false), .low)
        XCTAssertEqual(BatteryStyle.tone(level: 0.3, charging: false), .medium)
        XCTAssertEqual(BatteryStyle.tone(level: 0.8, charging: false), .normal)
        XCTAssertEqual(BatteryStyle.tone(level: 0.1, charging: true), .charging)
    }
}
