import Foundation

enum AppRoute: Hashable {
    case today, info, weather, school, finance, device
    case court(code: String?, date: String?)

    private var destination: String {
        switch self {
        case .today: return "today"
        case .info: return "info"
        case .weather: return "weather"
        case .school: return "school"
        case .finance: return "finance"
        case .device: return "device"
        case .court: return "court"
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "iwidget"
        components.host = destination
        if case let .court(code, date) = self {
            var items: [URLQueryItem] = []
            if let code { items.append(URLQueryItem(name: "code", value: code)) }
            if let date { items.append(URLQueryItem(name: "date", value: date)) }
            if !items.isEmpty { components.queryItems = items }
        }
        return components.url!
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "iwidget", components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { return nil }
        let items = components.queryItems ?? []
        guard items.isEmpty || components.host == "court" else { return nil }
        switch components.host {
        case "today": self = .today
        case "info": self = .info
        case "weather": self = .weather
        case "school": self = .school
        case "finance": self = .finance
        case "device": self = .device
        case "court":
            guard items.allSatisfy({ ["code", "date"].contains($0.name) && $0.value != nil }),
                  Set(items.map(\.name)).count == items.count else { return nil }
            let code = items.first { $0.name == "code" }?.value
            let date = items.first { $0.name == "date" }?.value
            if let code, !CourtCatalog.all.contains(where: { $0.code == code }) { return nil }
            if let date, Self.calendarDate(date) == nil { return nil }
            self = .court(code: code, date: date)
        default: return nil
        }
    }

    static func calendarDate(_ text: String) -> Date? {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = dateFormatter()
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else { return nil }
        return date
    }

    static func dateString(_ date: Date) -> String { dateFormatter().string(from: date) }

    private static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}
