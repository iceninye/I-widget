import XCTest

final class WidgetExportTests: XCTestCase {
    private let generatedAt = Date(timeIntervalSince1970: 1_795_586_730)

    func testJSONUsesStableSchemaAndUTCDates() throws {
        let data = try snapshot().jsonData()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        XCTAssertEqual(root["serviceDate"] as? String, "20261023")
        XCTAssertEqual(root["generatedAt"] as? String, "2026-11-25T06:05:30Z")
        XCTAssertEqual(root["theme"] as? String, "classic")
        XCTAssertEqual(Set(root.keys), Set([
            "schemaVersion", "generatedAt", "serviceDate", "theme", "freshness", "system",
            "duty", "school", "weather", "warnings", "train", "environment", "vps", "courts",
        ]))
    }

    func testRoundTripPreservesSnapshot() throws {
        let original = snapshot()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetExport.self, from: original.jsonData())
        XCTAssertEqual(decoded, original)
    }

    func testNilOptionalFieldsAreOmitted() throws {
        let data = try snapshot().jsonData()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let system = try XCTUnwrap(root["system"] as? [String: Any])
        let battery = try XCTUnwrap(system["battery"] as? [String: Any])

        XCTAssertNil(battery["level"])
        XCTAssertNil(system["latestOS"])
        XCTAssertNil(system["bootAt"])
    }

    func testPayloadLimitIsEnforcedBeforeWriting() {
        let oversized = snapshot(environmentLines: [
            WidgetLine(label: "large", value: String(repeating: "x", count: WidgetSchema.maxBytes))
        ])
        XCTAssertThrowsError(try oversized.jsonData()) { error in
            guard case ScriptableBridgeError.payloadTooLarge(let bytes) = error else {
                return XCTFail("Expected payloadTooLarge, got \(error)")
            }
            XCTAssertGreaterThan(bytes, WidgetSchema.maxBytes)
        }
    }

    func testOnlyInvalidBookmarksRequireReauthorization() {
        XCTAssertTrue(ScriptableBridgeError.bookmarkMissing.needsReauthorization)
        XCTAssertTrue(ScriptableBridgeError.bookmarkInvalid.needsReauthorization)
        XCTAssertFalse(ScriptableBridgeError.providerUnavailable.needsReauthorization)
        XCTAssertFalse(ScriptableBridgeError.coordinationConflict.needsReauthorization)
        XCTAssertFalse(ScriptableBridgeError.writeFailed("disk full").needsReauthorization)
    }

    func testSuccessfulWriteDoesNotClaimCloudSync() {
        let status = ScriptableBridgeStatus.written(at: generatedAt)
        XCTAssertEqual(status.state, .writtenAwaitingCloud)
        XCTAssertEqual(status.lastSuccessAt, generatedAt)
        XCTAssertTrue(status.message.contains("唔代表 Widget 已刷新"))
    }

    func testSuccessfulWriteAdvancesLastSuccessTime() {
        let previous = generatedAt.addingTimeInterval(-3_600)
        let status = ScriptableBridgeStatus.written(at: generatedAt)
        XCTAssertGreaterThan(status.lastSuccessAt ?? .distantPast, previous)
    }

    private func snapshot(environmentLines: [WidgetLine] = []) -> WidgetExport {
        WidgetExport(
            schemaVersion: 1,
            generatedAt: generatedAt,
            serviceDate: "20261023",
            theme: "classic",
            freshness: WidgetFreshness(
                today: generatedAt, info: nil, schedule: nil, weather: nil,
                warningsToday: nil, warningsInfo: nil, court: nil
            ),
            system: WidgetSystem(
                capturedAt: generatedAt,
                battery: WidgetBattery(
                    level: nil, charging: false, fullyCharged: false, lowPowerMode: false,
                    estimatedText: "未有資料", rateText: "估算中"
                ),
                storage: WidgetStorage(
                    freeBytes: nil, totalBytes: nil, freeText: "—", totalText: "—", usedText: "—"
                ),
                memory: WidgetMemory(totalBytes: nil, availableBytes: nil, lines: []),
                uptimeSeconds: nil,
                uptimeText: "—",
                bootAt: nil,
                systemName: "iOS",
                systemVersion: "27.0",
                versionText: "iOS 27.0",
                latestOS: nil,
                osStatus: "unknown"
            ),
            duty: WidgetDuty(
                configured: false, failed: false, today: nil, tomorrow: nil, events: [],
                weekText: nil, nextHoliday: nil, detailLines: []
            ),
            school: WidgetSchool(
                failed: [],
                today: WidgetSchoolDay(cycle: [], items: []),
                tomorrow: WidgetSchoolDay(cycle: [], items: [])
            ),
            weather: WidgetWeather(
                available: false, fetchedAt: nil, currentTemp: nil,
                today: nil, tomorrow: nil, daily: []
            ),
            warnings: WidgetWarnings(available: false, items: []),
            train: WidgetTrain(available: false, stateText: "未有資料", message: ""),
            environment: WidgetEnvironment(sections: [
                WidgetInfoSection(id: "gold", title: "黃金", lines: environmentLines)
            ]),
            vps: WidgetVPS(configured: false, available: false, failed: false, lines: []),
            courts: WidgetCourts(listDate: nil, updatedAt: nil, items: [])
        )
    }
}
