import XCTest

final class VPSStatusTests: XCTestCase {
    private func parse(_ json: String) throws -> VPSStatus {
        try VPSAPI.parse(Data(json.utf8))
    }

    func testParseScriptOutput() throws {
        let json = """
        {"os":"Ubuntu 24.04.3 LTS","kernel":"6.8.0-48-generic","upgradable":12,"security":3,
         "reboot_required":true,"xray_running":true,"hysteria2_listening":false,
         "updated_at":"2026-10-23T13:50:00.123456+00:00"}
        """
        let status = try parse(json)
        XCTAssertEqual(status.os, "Ubuntu 24.04.3 LTS")
        XCTAssertEqual(status.upgradable, 12)
        XCTAssertEqual(status.security, 3)
        XCTAssertTrue(status.rebootRequired)
        XCTAssertEqual(status.xrayRunning, true)
        XCTAssertEqual(status.hysteria2Listening, false)
        XCTAssertEqual(status.updatedAt, ISO8601DateFormatter().date(from: "2026-10-23T13:50:00Z"))
    }

    func testParseOldScriptWithoutProxyFields() throws {
        let status = try parse(#"{"os":"Ubuntu","upgradable":0}"#)
        XCTAssertNil(status.xrayRunning)
        XCTAssertNil(status.updatedAt)
        XCTAssertFalse(status.rebootRequired)
    }

    func testParseRejectsMissingRequiredFields() {
        XCTAssertThrowsError(try parse("{}"))
        XCTAssertThrowsError(try parse(#"{"os":"x"}"#))
    }

    func testHealth() throws {
        XCTAssertEqual(VPSAPI.health(try parse(#"{"os":"x","upgradable":0,"xray_running":true,"hysteria2_listening":true}"#)), .ok)
        XCTAssertEqual(VPSAPI.health(try parse(#"{"os":"x","upgradable":2,"security":0}"#)), .attention)
        XCTAssertEqual(VPSAPI.health(try parse(#"{"os":"x","upgradable":2,"security":1}"#)), .problem)
        XCTAssertEqual(VPSAPI.health(try parse(#"{"os":"x","upgradable":0,"reboot_required":true}"#)), .problem)
        XCTAssertEqual(VPSAPI.health(try parse(#"{"os":"x","upgradable":0,"xray_running":false}"#)), .problem)
    }

    func testUpdatesText() throws {
        XCTAssertEqual(VPSAPI.updatesText(try parse(#"{"os":"x","upgradable":0}"#)), "已是最新")
        XCTAssertEqual(VPSAPI.updatesText(try parse(#"{"os":"x","upgradable":4}"#)), "4 項更新")
        XCTAssertEqual(VPSAPI.updatesText(try parse(#"{"os":"x","upgradable":4,"security":2}"#)), "4 項更新（2 項安全）")
    }

    func testURLMustBeHTTPS() {
        XCTAssertNil(VPSAPI.url("http://example.com/status.json"))
        XCTAssertNil(VPSAPI.url("example.com/status.json"))
        XCTAssertNil(VPSAPI.url(nil))
        XCTAssertEqual(VPSAPI.url("  https://example.com/status.json \n")?.host, "example.com")
        XCTAssertEqual(VPSAPI.statusURL(nil), VPSAPI.defaultURL)
        XCTAssertEqual(VPSAPI.statusURL("  "), VPSAPI.defaultURL)
        XCTAssertEqual(VPSAPI.statusURL("https://example.com/status.json")?.host, "example.com")
        XCTAssertNil(VPSAPI.statusURL("http://example.com/status.json"))
    }
}
