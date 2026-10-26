import Foundation

/// 司法機構「法庭日誌」嘅一個案件表（view.jsp 嘅法院代碼）。
struct CourtInfo: Equatable {
    let code: String
    let name: String
}

enum CourtCatalog {
    static let all = [
        CourtInfo(code: "CFA", name: "終審法院"),
        CourtInfo(code: "CACFI", name: "高院上訴／原訟"),
        CourtInfo(code: "HCMC", name: "高院聆案官"),
        CourtInfo(code: "MCL", name: "高院三分鐘內庭"),
        CourtInfo(code: "O14", name: "高院簡易判決"),
        CourtInfo(code: "DC", name: "區域法院"),
        CourtInfo(code: "DCMC", name: "區院聆案官"),
        CourtInfo(code: "FMC", name: "家事法庭"),
        CourtInfo(code: "LANDS", name: "土地審裁處"),
        CourtInfo(code: "ALLMAG", name: "所有裁判法院"),
        CourtInfo(code: "ETNMAG", name: "東區裁判法院"),
        CourtInfo(code: "KCMAG", name: "九龍城裁判法院"),
        CourtInfo(code: "KTMAG", name: "觀塘裁判法院"),
        CourtInfo(code: "WKMAG", name: "西九龍裁判法院"),
        CourtInfo(code: "STMAG", name: "沙田裁判法院"),
        CourtInfo(code: "FLMAG", name: "粉嶺裁判法院"),
        CourtInfo(code: "TMMAG", name: "屯門裁判法院"),
        CourtInfo(code: "LT", name: "勞資審裁處"),
        CourtInfo(code: "SMT", name: "小額錢債審裁處"),
        CourtInfo(code: "CRC", name: "死因裁判法庭"),
    ]

    static func name(_ code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }
}

/// 一個聆訊。刻意唔載入訴訟各方：網頁話明個人資料不可再用，所以只留法庭、時間、案件編號同法官。
struct CourtCase: Codable, Equatable {
    var room: String
    var judge: String
    var minutes: Int?
    var caseNo: String

    var timeText: String {
        guard let minutes else { return "--:--" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// 一個法院一日嘅案件表。`error` 代表讀取失敗而且冇快取。
struct CourtDay: Codable, Equatable {
    var code: String
    var dateCode: String
    var total: Int
    var cases: [CourtCase]
    var error = false

    var name: String { CourtCatalog.name(code) }

    /// 仲未完嘅聆訊（開始後 20 分鐘內當仲進行緊）；`now` 為當日分鐘數，`nil` 代表唔係今日，全部都算。
    func upcoming(afterMinute now: Int?) -> [CourtCase] {
        let sorted = cases.enumerated().sorted { lhs, rhs in
            switch (lhs.element.minutes, rhs.element.minutes) {
            case let (a?, b?): return a == b ? lhs.offset < rhs.offset : a < b
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
        guard let now else { return sorted }
        return sorted.filter { ($0.minutes ?? Int.max) >= now - 20 }
    }
}

enum CourtList {
    // MARK: 解析

    private enum Column { case court, judge, time, caseNo }

    /// 解析 view.jsp 嘅 HTML（Word 匯出嘅表格）。按欄位標題對位，唔靠固定欄序；
    /// 法庭、法官、時間留空（合併儲存格）就沿用上一行。
    static func parse(_ html: String) -> [CourtCase] {
        var columns: [Column: Int] = [:]
        var headerCount = 0
        var cases: [CourtCase] = []
        var room = "", judge = "", minutes: Int?

        for row in matches(rowPattern, in: html) {
            let cells = matches(cellPattern, in: row).map(cleanText)
            guard !cells.isEmpty else { continue }

            if cells.contains(where: { $0.contains("案件編號") || $0.lowercased().contains("case no") }) {
                columns = [:]
                for (index, text) in cells.enumerated() {
                    if let column = column(for: text), columns[column] == nil { columns[column] = index }
                }
                headerCount = cells.count
                room = ""; judge = ""; minutes = nil
                continue
            }
            guard columns[.caseNo] != nil else { continue }

            // 前面嘅格因為 rowspan 冇出現時，由右對齊
            let offset = max(headerCount - cells.count, 0)
            func cell(_ column: Column) -> String? {
                guard let index = columns[column], index - offset >= 0, index - offset < cells.count else { return nil }
                return cells[index - offset]
            }
            guard let caseNo = cell(.caseNo), caseNo.contains(where: \.isNumber) else { continue }
            if let value = cell(.court), !value.isEmpty { room = value }
            if let value = cell(.judge), !value.isEmpty { judge = value }
            if let value = cell(.time), !value.isEmpty { minutes = parseTime(value) ?? minutes }
            cases.append(CourtCase(room: room, judge: judge, minutes: minutes, caseNo: caseNo))
        }
        return cases
    }

    private static func column(for text: String) -> Column? {
        if text.contains("案件編號") || text.lowercased().contains("case no") { return .caseNo }
        if text.contains("時間") { return .time }
        if ["法官", "聆案官", "裁判官", "審裁", "驗屍官", "司法"].contains(where: text.contains) { return .judge }
        if text.contains("法庭") || text.contains("法院") { return .court }
        return nil
    }

    private static let rowPattern = try! NSRegularExpression(pattern: "<tr[\\s>].*?</tr>", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let cellPattern = try! NSRegularExpression(pattern: "<t[dh][\\s>].*?</t[dh]>", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let breakPattern = try! NSRegularExpression(pattern: "<br[^>]*>|</p>", options: .caseInsensitive)
    private static let tagPattern = try! NSRegularExpression(pattern: "<[^>]*>")
    private static let timePattern = try! NSRegularExpression(
        pattern: "(上午|下午|am|pm|a\\.m\\.|p\\.m\\.)?\\s*(\\d{1,2})\\s*(?:[:：.時]\\s*(\\d{1,2}))?\\s*(上午|下午|am|pm|a\\.m\\.|p\\.m\\.)?",
        options: .caseInsensitive
    )

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    static func cleanText(_ html: String) -> String {
        var text = replace(breakPattern, in: html, with: " ")
        text = replace(tagPattern, in: text, with: "")
        text = decodeEntities(text)
        let words = text.split(whereSeparator: { $0.isWhitespace || $0 == "\u{00A0}" })
        return words.joined(separator: " ")
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'", "&#39;": "'"]
        var result = text
        for (key, value) in named { result = result.replacingOccurrences(of: key, with: value) }
        guard result.contains("&#"), let numeric = try? NSRegularExpression(pattern: "&#([xX]?)([0-9a-fA-F]+);") else { return result }
        let ns = result as NSString
        var output = ""
        var last = 0
        for match in numeric.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let hex = !ns.substring(with: match.range(at: 1)).isEmpty
            if let value = UInt32(ns.substring(with: match.range(at: 2)), radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                output.unicodeScalars.append(scalar)
            }
            last = match.range.location + match.range.length
        }
        output += ns.substring(from: last)
        return output
    }

    /// `9:30 am`、`09:30`、`下午2:30`、`10時15分` → 當日分鐘數。
    static func parseTime(_ text: String) -> Int? {
        let ns = text as NSString
        guard let match = timePattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range).lowercased()
        }
        guard var hour = group(2).flatMap({ Int($0) }) else { return nil }
        let minute = group(3).flatMap { Int($0) } ?? 0
        // 冇冒號、冇「時」、冇 am／pm 嘅純數字唔係時間
        let marker = group(1) ?? group(4)
        let hasSeparator = text.contains(where: { ":：.時".contains($0) })
        guard marker != nil || hasSeparator, hour < 24, minute < 60 else { return nil }
        if let marker {
            let pm = marker.hasPrefix("p") || marker == "下午"
            if pm, hour < 12 { hour += 12 }
            if !pm, hour == 12 { hour = 0 }
        }
        return hour * 60 + minute
    }

    // MARK: 日期

    /// 要睇邊日嘅案件表：18:30 後（案件表大約嗰陣公布下一個工作天）轉去下一個工作天；週末睇星期一。
    static func listDate(now: Date, calendar: Calendar = ICalendar.hongKong) -> Date {
        var day = calendar.startOfDay(for: now)
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if minute >= 18 * 60 + 30 { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        while [1, 7].contains(calendar.component(.weekday, from: day)) {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    /// `26102026`（DDMMYYYY）。
    static func dateCode(_ day: Date, calendar: Calendar = ICalendar.hongKong) -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: day)
        return String(format: "%02d%02d%04d", parts.day ?? 0, parts.month ?? 0, parts.year ?? 0)
    }

    /// 當日分鐘數；唔係今日就 `nil`。
    static func minuteOfDay(now: Date, listDate: Date, calendar: Calendar = ICalendar.hongKong) -> Int? {
        guard calendar.isDate(now, inSameDayAs: listDate) else { return nil }
        return calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    }

    static func dayText(_ day: Date, now: Date, calendar: Calendar = ICalendar.hongKong) -> String {
        let weekdays = ["日", "一", "二", "三", "四", "五", "六"]
        let weekday = weekdays[calendar.component(.weekday, from: day) - 1]
        let date = "\(calendar.component(.month, from: day))/\(calendar.component(.day, from: day))（\(weekday)）"
        if calendar.isDate(day, inSameDayAs: now) { return "今日 \(date)" }
        return date
    }

    // MARK: 讀取

    static func url(code: String, dateCode: String) -> URL? {
        URL(string: "https://e-services.judiciary.hk/dcl/view.jsp?lang=tc&date=\(dateCode)&court=\(code)")
    }

    /// 網站要瀏覽器嘅 User-Agent，否則回 404。
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private static func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://e-services.judiciary.hk/dcl/index.jsp?lang=tc", forHTTPHeaderField: "Referer")
        request.setValue("zh-HK,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 4_000_000 else {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func cacheKey(_ code: String, _ dateCode: String) -> String { "court.\(code).\(dateCode)" }

    /// 10 分鐘內嘅快取直接用；讀取失敗就用舊快取，冇快取先標記 error。
    static func load(code: String, day: Date, now: Date) async -> CourtDay {
        let dateCode = dateCode(day)
        let key = cacheKey(code, dateCode)
        if let fresh = DataCache.fresh(CourtDay.self, key: key, maxAge: 10 * 60, now: now) { return fresh }
        if let url = url(code: code, dateCode: dateCode), let html = try? await fetch(url) {
            let cases = parse(html)
            let result = CourtDay(code: code, dateCode: dateCode, total: cases.count, cases: Array(cases.prefix(300)))
            DataCache.save(result, key: key, stamped: now)
            return result
        }
        return DataCache.load(CourtDay.self, key: key) ?? CourtDay(code: code, dateCode: dateCode, total: 0, cases: [], error: true)
    }

    static func cached(code: String, day: Date) -> CourtDay {
        let dateCode = dateCode(day)
        return DataCache.load(CourtDay.self, key: cacheKey(code, dateCode)) ?? CourtDay(code: code, dateCode: dateCode, total: 0, cases: [], error: true)
    }

    static func loadAll(codes: [String], day: Date, now: Date) async -> [CourtDay] {
        await withTaskGroup(of: (Int, CourtDay).self) { group in
            for (index, code) in codes.enumerated() {
                group.addTask { (index, await load(code: code, day: day, now: now)) }
            }
            var results: [(Int, CourtDay)] = []
            for await item in group { results.append(item) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
