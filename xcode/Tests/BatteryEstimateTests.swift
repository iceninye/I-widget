import XCTest

final class BatteryEstimateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(_ minutes: Double, _ level: Double, charging: Bool = false) -> BatterySample {
        BatterySample(time: start.addingTimeInterval(minutes * 60), level: level, charging: charging)
    }

    func testDischargingRate() {
        // 1 小時跌 10%，剩 50% → 約 5 小時
        let samples = [sample(0, 0.60), sample(30, 0.55), sample(60, 0.50)]
        guard case .remaining(let seconds) = BatteryHistory.estimate(samples, now: samples.last!.time) else {
            return XCTFail("expected remaining")
        }
        XCTAssertEqual(seconds, 5 * 3_600, accuracy: 60)
        XCTAssertEqual(BatteryHistory.text(.remaining(seconds)), "約剩 5 小時")
    }

    func testIgnoresSamplesBeforeUnplugging() {
        let samples = [sample(0, 0.90, charging: true), sample(30, 1.0, charging: true), sample(40, 0.99)]
        XCTAssertEqual(BatteryHistory.estimate(samples, now: samples.last!.time), .learning)
    }

    func testChargingUntilFull() {
        let samples = [sample(0, 0.40, charging: true), sample(60, 0.70, charging: true)]
        guard case .untilFull(let seconds) = BatteryHistory.estimate(samples, now: samples.last!.time) else {
            return XCTFail("expected untilFull")
        }
        XCTAssertEqual(seconds, 3_600, accuracy: 60)
        XCTAssertEqual(BatteryHistory.estimate([sample(0, 1.0, charging: true)], now: start), .full)
    }

    func testPercentPerHour() {
        let samples = [sample(0, 0.60), sample(60, 0.50)]
        XCTAssertEqual(BatteryHistory.percentPerHour(samples, now: samples.last!.time) ?? 0, 10, accuracy: 0.01)
        XCTAssertNil(BatteryHistory.percentPerHour([sample(0, 0.6)], now: start))
    }

    func testNeedsEnoughChange() {
        let samples = [sample(0, 0.80), sample(60, 0.79)]
        XCTAssertEqual(BatteryHistory.estimate(samples, now: samples.last!.time), .learning)
        XCTAssertEqual(BatteryHistory.estimate([], now: start), .unknown)
    }

    func testAppendingReplacesCloseSamplesAndDropsOld() {
        var samples = [sample(-25 * 60, 0.9), sample(0, 0.8)]
        samples = BatteryHistory.appending(sample(2, 0.79), to: samples)
        XCTAssertEqual(samples, [sample(2, 0.79)])
        samples = BatteryHistory.appending(sample(30, 0.75), to: samples)
        XCTAssertEqual(samples.count, 2)
    }

    func testDurationText() {
        XCTAssertEqual(BatteryHistory.duration(45 * 60), "45 分")
        XCTAssertEqual(BatteryHistory.duration(5 * 3_600 + 20 * 60), "5 小時 20 分")
        XCTAssertEqual(BatteryHistory.duration(12 * 3_600 + 20 * 60), "12 小時")
        XCTAssertEqual(BatteryHistory.duration(50 * 3_600), "2 日 2 小時")
    }
}
