import XCTest

final class AppRouteTests: XCTestCase {
    func testRoutesRoundTrip() {
        let routes: [AppRoute] = [.today, .info, .weather, .school, .finance, .device,
                                  .court(code: nil, date: nil), .court(code: "DC", date: "2026-10-28")]
        for route in routes { XCTAssertEqual(AppRoute(url: route.url), route) }
    }

    func testRejectsUnsupportedAndSensitiveParameters() throws {
        let invalid = ["https://today", "iwidget://unknown", "iwidget://today/path",
                       "iwidget://user:secret@today", "iwidget://today:80", "iwidget://today#secret",
                       "iwidget://today?token=secret", "iwidget://court?token=secret",
                       "iwidget://court?code=INVALID", "iwidget://court?code=DC&code=CFA",
                       "iwidget://court?date=2026-02-30", "iwidget://court?date=not-a-date",
                       "iwidget://court?code"]
        for text in invalid { XCTAssertNil(AppRoute(url: try XCTUnwrap(URL(string: text))), text) }
    }

    func testHongKongDateBoundary() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-28T16:01:00Z"))
        XCTAssertEqual(AppRoute.dateString(date), "2026-10-29")
        XCTAssertNotNil(AppRoute.calendarDate("2028-02-29"))
        XCTAssertNil(AppRoute.calendarDate("2026-02-29"))
    }
}
