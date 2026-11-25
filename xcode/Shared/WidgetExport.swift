import Foundation

enum WidgetSchema {
    static let version = 1
    static let maxBytes = 512 * 1024
    static let maxCourts = 4
    static let maxCasesPerCourt = 80

    static let themes = ["classic", "ocean", "sunset", "forest", "violet", "mono"]
}

struct WidgetExport: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let serviceDate: String
    let theme: String
    let freshness: WidgetFreshness
    let system: WidgetSystem
    let duty: WidgetDuty
    let school: WidgetSchool
    let weather: WidgetWeather
    let warnings: WidgetWarnings
    let train: WidgetTrain
    let environment: WidgetEnvironment
    let vps: WidgetVPS
    let courts: WidgetCourts

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= WidgetSchema.maxBytes else {
            throw ScriptableBridgeError.payloadTooLarge(data.count)
        }
        return data
    }
}

struct WidgetFreshness: Codable, Sendable, Equatable {
    let today: Date?
    let info: Date?
    let schedule: Date?
    let weather: Date?
    let warningsToday: Date?
    let warningsInfo: Date?
    let court: Date?
}

struct WidgetSystem: Codable, Sendable, Equatable {
    let capturedAt: Date
    let battery: WidgetBattery
    let storage: WidgetStorage
    let memory: WidgetMemory
    let uptimeSeconds: TimeInterval?
    let uptimeText: String
    let bootAt: Date?
    let systemName: String
    let systemVersion: String
    let versionText: String
    let latestOS: String?
    let osStatus: String
}

struct WidgetBattery: Codable, Sendable, Equatable {
    let level: Double?
    let charging: Bool
    let fullyCharged: Bool
    let lowPowerMode: Bool
    let estimatedText: String
    let rateText: String
}

struct WidgetStorage: Codable, Sendable, Equatable {
    let freeBytes: Int64?
    let totalBytes: Int64?
    let freeText: String
    let totalText: String
    let usedText: String
}

struct WidgetMemory: Codable, Sendable, Equatable {
    let totalBytes: Int64?
    let availableBytes: Int64?
    let lines: [WidgetLine]
}

struct WidgetDuty: Codable, Sendable, Equatable {
    let configured: Bool
    let failed: Bool
    let today: WidgetDutyDay?
    let tomorrow: WidgetDutyDay?
    let events: [WidgetDutyEvent]
    let weekText: String?
    let nextHoliday: WidgetHoliday?
    let detailLines: [WidgetLine]
}

struct WidgetDutyDay: Codable, Sendable, Equatable {
    let date: String
    let code: String
    let title: String
    let times: String?
    let route: String?
    let mealText: String?
    let hoursText: String?
    let hint: String?
    let onAt: Date?
    let offAt: Date?
}

struct WidgetDutyEvent: Codable, Sendable, Equatable {
    let id: String
    let action: String
    let at: Date
    let displayAt: String
    let title: String
    let detail: String
    let place: String
    let note: String
}

struct WidgetHoliday: Codable, Sendable, Equatable {
    let title: String
    let rangeText: String
    let daysAway: Int
}

struct WidgetSchool: Codable, Sendable, Equatable {
    let failed: [String]
    let today: WidgetSchoolDay
    let tomorrow: WidgetSchoolDay
}

struct WidgetSchoolDay: Codable, Sendable, Equatable {
    let cycle: [String]
    let items: [WidgetSchoolItem]
}

struct WidgetSchoolItem: Codable, Sendable, Equatable {
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
}

struct WidgetWeather: Codable, Sendable, Equatable {
    let available: Bool
    let fetchedAt: Date?
    let currentTemp: Double?
    let today: WidgetWeatherDay?
    let tomorrow: WidgetWeatherDay?
    let daily: [WidgetDatedWeather]
}

struct WidgetWeatherDay: Codable, Sendable, Equatable {
    let code: Int
    let codeText: String
    let symbol: String
    let minTemp: Double
    let maxTemp: Double
    let tempText: String
    let rainChance: Int?
    let uvIndex: Double?
}

struct WidgetDatedWeather: Codable, Sendable, Equatable {
    let date: String
    let day: WidgetWeatherDay
}

struct WidgetWarnings: Codable, Sendable, Equatable {
    let available: Bool
    let items: [WidgetWarning]
}

struct WidgetWarning: Codable, Sendable, Equatable {
    let text: String
    let severe: Bool
}

struct WidgetTrain: Codable, Sendable, Equatable {
    let available: Bool
    let stateText: String
    let message: String
}

struct WidgetEnvironment: Codable, Sendable, Equatable {
    let sections: [WidgetInfoSection]
}

struct WidgetInfoSection: Codable, Sendable, Equatable {
    let id: String
    let title: String
    let lines: [WidgetLine]
}

struct WidgetLine: Codable, Sendable, Equatable {
    let label: String
    let value: String
}

struct WidgetVPS: Codable, Sendable, Equatable {
    let configured: Bool
    let available: Bool
    let failed: Bool
    let lines: [WidgetLine]
}

struct WidgetCourts: Codable, Sendable, Equatable {
    let listDate: Date?
    let updatedAt: Date?
    let items: [WidgetCourtDay]
}

struct WidgetCourtDay: Codable, Sendable, Equatable {
    let code: String
    let name: String
    let dateCode: String
    let fetchedAt: Date?
    let error: Bool
    let total: Int
    let truncated: Bool
    let categories: [WidgetCategoryCount]
    let deepLink: String
    let cases: [WidgetCourtCase]
}

struct WidgetCategoryCount: Codable, Sendable, Equatable {
    let category: String
    let title: String
    let count: Int
}

struct WidgetCourtCase: Codable, Sendable, Equatable {
    let room: String
    let judge: String
    let minutes: Int?
    let timeText: String
    let caseNo: String
    let nature: String?
    let offence: String?
    let category: String
    let categoryTitle: String
    let detailText: String
    let deepLink: String
}
