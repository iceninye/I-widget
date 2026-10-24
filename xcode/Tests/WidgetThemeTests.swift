import XCTest

final class WidgetThemeTests: XCTestCase {
    func testCyclesThroughEveryThemeAndWraps() {
        var theme = WidgetTheme.classic
        var seen: [WidgetTheme] = [theme]
        for _ in 1..<WidgetTheme.allCases.count {
            theme = theme.next
            seen.append(theme)
        }
        XCTAssertEqual(seen, WidgetTheme.allCases)
        XCTAssertEqual(theme.next, .classic)
    }

    func testLabelsAreUniqueAndStored() throws {
        XCTAssertEqual(Set(WidgetTheme.allCases.map(\.label)).count, WidgetTheme.allCases.count)
        let data = try JSONEncoder().encode(WidgetTheme.sunset)
        XCTAssertEqual(try JSONDecoder().decode(WidgetTheme.self, from: data), .sunset)
    }
}
