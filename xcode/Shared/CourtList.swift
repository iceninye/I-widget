import Foundation

/// 司法機構「法庭日誌」嘅一個案件表（view.jsp 嘅法院代碼）。
struct CourtInfo: Equatable, Sendable {
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

    static let magistrateCodes: Set<String> = ["ETNMAG", "KCMAG", "KTMAG", "WKMAG", "STMAG", "FLMAG", "TMMAG"]
    static let allCodes = all.map(\.code).filter { $0 != "ALLMAG" }

    static func selection(_ codes: [String]) -> [String] {
        guard !codes.isEmpty else { return allCodes }
        let known = Set(all.map(\.code))
        var seen = Set<String>()
        let unique = codes.filter { known.contains($0) && seen.insert($0).inserted }
        guard seen.contains("ALLMAG") else { return unique }
        if magistrateCodes.isSubset(of: seen) { return unique.filter { $0 != "ALLMAG" } }
        return unique.filter { !magistrateCodes.contains($0) }
    }

    static func name(_ code: String) -> String {
        all.first { $0.code == code }?.name ?? code
    }
}

/// 一個聆訊。刻意唔載入訴訟各方：網頁話明個人資料不可再用，所以只留法庭、時間、案件編號同法官。
struct CourtCase: Codable, Equatable, Sendable {
    var room: String
    var judge: String
    var minutes: Int?
    var caseNo: String
    /// 性質／控罪（例如「審訊」「答辯」）；只有按欄對位讀得到嘅行先有。舊快取冇呢欄，解碼成 nil。
    var nature: String? = nil

    var timeText: String {
        guard let minutes else { return "--:--" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 開始後呢個分鐘數內仍當作進行中。
    static let ongoingWindow = 20

    /// 相對於當日分鐘數（`nil` = 唔係今日）嘅進度。
    func status(atMinute now: Int?) -> CourtStatus {
        guard let now, let minutes else { return .scheduled }
        if minutes > now { return .upcoming }
        return now - minutes < Self.ongoingWindow ? .ongoing : .finished
    }
}

enum CourtStatus: Equatable {
    case scheduled   // 唔係今日或者冇時間
    case upcoming, ongoing, finished

    var text: String {
        switch self {
        case .scheduled: return "待審"
        case .upcoming: return "未開始"
        case .ongoing: return "進行中"
        case .finished: return "已過時間"
        }
    }
}

enum CourtSourceStatus: String, Codable, Sendable {
    case parsed, officialNoList, unavailable
}

struct CourtMetadata: Codable, Equatable, Sendable {
    var source: CourtSourceStatus = .parsed
    var publishedAt: Date? = nil
    var fetchedAt: Date? = nil
    var attemptedAt: Date? = nil
    var failure: String? = nil

    func isStale(at now: Date) -> Bool {
        guard let fetchedAt else { return true }
        return failure != nil || now < fetchedAt || now.timeIntervalSince(fetchedAt) >= 600
    }

    func label(total: Int, error: Bool, at now: Date) -> String {
        if error { return fetchedAt == nil ? "讀取失敗" : "更新失敗・舊資料" }
        if source == .unavailable { return "案件表未能確認" }
        if isStale(at: now) { return "快取・待更新" }
        return source == .officialNoList ? "官方未提供案件表" : "已解析 \(total) 宗"
    }
}

/// `error` 亦會標記更新失敗後保留嘅舊快取；唔代表當日冇聆訊。
struct CourtDay: Codable, Equatable, Sendable {
    var code: String
    var dateCode: String
    var total: Int
    var cases: [CourtCase]
    var error = false
    var metadata = CourtMetadata()

    var name: String { CourtCatalog.name(code) }

    /// 按時間排好嘅全部聆訊（冇時間嘅排最後，同時間保持原本次序）。
    var sortedCases: [CourtCase] {
        cases.enumerated().sorted { lhs, rhs in
            switch (lhs.element.minutes, rhs.element.minutes) {
            case let (a?, b?): return a == b ? lhs.offset < rhs.offset : a < b
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// 只列時間嚴格晚於目前分鐘嘅排期；未知時間唔當作即將開庭。
    func upcoming(afterMinute now: Int?) -> [CourtCase] {
        guard let now else { return sortedCases }
        return sortedCases.filter { $0.minutes.map { $0 > now } ?? false }
    }
}

/// Timeline 只保留可見兩行及數量／來源狀態，唔複製整份案件表。
struct CourtSummary: Equatable, Sendable {
    let code: String
    let dateCode: String
    let total: Int
    let rows: [CourtCase]
    let unknownTimeCount: Int
    let error: Bool
    let metadata: CourtMetadata

    init(day: CourtDay, at date: Date, listDate: Date) {
        code = day.code
        dateCode = day.dateCode
        total = day.total
        rows = Array(day.upcoming(afterMinute: CourtList.minuteOfDay(now: date, listDate: listDate)).prefix(2))
        unknownTimeCount = day.cases.filter { $0.minutes == nil }.count
        error = day.error
        metadata = day.metadata
    }
}

struct CourtPageState: Codable, Equatable, Sendable {
    var page: Int = 0
    var anchoredAt: Date

    func page(at date: Date, count: Int, autoRotate: Bool) -> Int {
        let steps = autoRotate ? Int(max(0, date.timeIntervalSince(anchoredAt)) / CourtPaging.interval) : 0
        return CourtPaging.normalized(page + steps, count: count)
    }
}

enum CourtPaging {
    static let courtsPerPage = 3
    static let interval: TimeInterval = 600

    static func pageCount(for courtCount: Int) -> Int {
        max(1, (max(0, courtCount) + courtsPerPage - 1) / courtsPerPage)
    }

    static func normalized(_ page: Int, count: Int) -> Int {
        let count = max(1, count)
        return ((page % count) + count) % count
    }

    static func indices(page: Int, courtCount: Int) -> Range<Int> {
        let start = normalized(page, count: pageCount(for: courtCount)) * courtsPerPage
        return start..<min(start + courtsPerPage, max(0, courtCount))
    }

    static func configurationKey(codes: [String], autoRotate: Bool) -> String {
        "court.pages.v1.\(CourtCatalog.selection(codes).joined(separator: ".")).\(autoRotate)"
    }

    static func dates(now: Date, state: CourtPageState, autoRotate: Bool) -> [Date] {
        let horizon = now.addingTimeInterval(12 * interval)
        let elapsed = max(0, now.timeIntervalSince(state.anchoredAt))
        let next = autoRotate ? state.anchoredAt.addingTimeInterval((floor(elapsed / interval) + 1) * interval)
            : now.addingTimeInterval(interval)
        var dates = [now]
        for index in 0..<12 {
            let date = next.addingTimeInterval(Double(index) * interval)
            if date < horizon { dates.append(date) }
        }
        let calendar = ICalendar.hongKong
        if let boundary = calendar.nextDate(after: now, matching: DateComponents(hour: 18, minute: 30), matchingPolicy: .nextTime),
           boundary < horizon { dates.append(boundary) }
        return Array(Set(dates)).sorted()
    }
}

/// Widget 同 app 之間嘅連結：`iwidget://court?code=DC&case=DCCJ%201%2F2026&t=570`。
struct CourtLink: Equatable {
    var code: String
    var caseNo: String?
    var minutes: Int?

    static let scheme = "iwidget"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "court"
        var items = [URLQueryItem(name: "code", value: code)]
        if let caseNo { items.append(URLQueryItem(name: "case", value: caseNo)) }
        if let minutes { items.append(URLQueryItem(name: "t", value: String(minutes))) }
        components.queryItems = items
        return components.url ?? URL(string: "\(Self.scheme)://court")!
    }

    init(code: String, caseNo: String? = nil, minutes: Int? = nil) {
        self.code = code
        self.caseNo = caseNo
        self.minutes = minutes
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "court",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        self.code = code
        caseNo = items.first { $0.name == "case" }?.value
        minutes = items.first { $0.name == "t" }?.value.flatMap { Int($0) }
    }

    /// 喺某日案件表搵返連結指向嘅聆訊：案號加時間都對得上先，否則只對案號。
    func match(in day: CourtDay) -> CourtCase? {
        guard let caseNo else { return nil }
        let same = day.sortedCases.filter { $0.caseNo == caseNo }
        return same.first { $0.minutes == minutes } ?? same.first
    }
}

extension CourtCase {
    func link(code: String) -> CourtLink { CourtLink(code: code, caseNo: caseNo, minutes: minutes) }
}

enum CourtLayout {
    /// 將 `budget` 行派畀各法院：每個先攤平均，唔夠用嘅就將餘額畀其他仲有嘢睇嘅法院；每個至少 1 行。
    static func allocate(counts: [Int], budget: Int) -> [Int] {
        guard !counts.isEmpty else { return [] }
        var rows = Array(repeating: 1, count: counts.count)
        var left = max(budget - counts.count, 0)
        while left > 0 {
            var gave = false
            for index in counts.indices where left > 0 && rows[index] < counts[index] {
                rows[index] += 1
                left -= 1
                gave = true
            }
            if !gave { break }
        }
        return rows
    }
}

enum CourtList {
    // MARK: 解析

    private enum Column { case court, judge, time, caseNo, nature }

    private typealias Fields = (room: String?, judge: String?, time: String?, caseNo: String?, nature: String?)

    /// 解析 view.jsp 嘅 HTML（Word 匯出嘅表格）。
    ///
    /// 已用真實頁面（DC、HCMC、LANDS、CACFI、FMC、LT、SMT、CRC、MCL 同七個裁判法院）驗證過嘅規則：
    /// - 欄位按標題對位（表頭可以喺較早嘅 table）；格數齊全嘅行按欄讀。
    /// - 有合併（缺格）嘅行按內容認：時間、案件編號、法庭、法官，其餘格唔使理。
    /// - 法庭／法官／時間留空就沿用上一行；LT、SMT、MCL、裁判法院嘅法庭同法官喺橫幅行。
    /// - 冇案件編號嘅行（批量傳票、「見附頁」）唔算聆訊，但時間照樣沿用。
    static func parse(_ html: String) -> [CourtCase] {
        var columns: [Column: Int] = [:]
        var headerCount = 0
        var cases: [CourtCase] = []
        var room = "", judge = "", minutes: Int?

        for row in matches(rowPattern, in: html) {
            let raw = matches(cellPattern, in: row).map(cleanText)
            let cells = raw.filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }

            if cells.contains(where: isCaseHeader) {
                var found: [Column: Int] = [:]
                for (index, text) in raw.enumerated() {
                    if let column = column(for: text), found[column] == nil { found[column] = index }
                }
                // 英文標題行、裁判法院嘅單格標題認唔到幾多欄，唔好當成新表頭
                if found.count >= 2 {
                    columns = found
                    headerCount = raw.count
                    room = ""; judge = ""; minutes = nil
                }
                continue
            }

            let hasTime = cells.contains(where: isTimeCell)
            let hasCase = cells.contains(where: isCaseCell)
            if !hasTime && !hasCase {
                if cells.count <= 3 { applyBanner(cells, room: &room, judge: &judge, minutes: &minutes) }
                continue
            }

            let fields: Fields
            if columns[.caseNo] != nil, raw.count == headerCount {
                func at(_ column: Column) -> String? {
                    guard let index = columns[column], index < raw.count, !raw[index].isEmpty else { return nil }
                    return raw[index]
                }
                fields = (at(.court), at(.judge), at(.time), at(.caseNo), at(.nature))
            } else {
                fields = classify(cells, expectRoom: columns[.court] != nil, expectJudge: columns[.judge] != nil)
            }

            if let value = fields.room {
                let text = roomText(value)
                if text != room { minutes = nil }
                room = text
            }
            if let value = fields.judge { judge = chinesePart(value) }
            if let value = fields.time, let parsed = parseTime(value) { minutes = parsed }
            guard let caseNo = fields.caseNo, firstMatch(caseNoPattern, in: caseNo) != nil else { continue }
            cases.append(CourtCase(room: room, judge: judge, minutes: minutes, caseNo: trimCaseNo(caseNo), nature: natureText(fields.nature)))
        }
        return cases
    }

    /// 格數唔齊（合併儲存格）嘅行：按內容認出時間、案件編號，必要時法庭同法官。
    private static func classify(_ cells: [String], expectRoom: Bool, expectJudge: Bool) -> Fields {
        var result: Fields = (nil, nil, nil, nil, nil)
        for cell in cells {
            if result.time == nil, isTimeCell(cell) {
                result.time = cell
            } else if result.caseNo == nil, isCaseCell(cell) {
                result.caseNo = cell
            } else if expectRoom, result.room == nil, isRoomCell(cell) {
                result.room = cell
            } else if expectJudge, result.judge == nil, isJudgeCell(cell) {
                result.judge = cell
            }
        }
        return result
    }

    /// 橫幅行（≤3 格、冇時間冇案件編號）：`法庭 : 第42庭`、`第 1庭（1樓）`、`裁判官 Magistrate : | 某某裁判官`。
    private static func applyBanner(_ cells: [String], room: inout String, judge: inout String, minutes: inout Int?) {
        for cell in cells {
            if cell.hasSuffix(":") || cell.hasSuffix("：") { continue }  // 標籤格，值喺下一格
            if let value = labelled(cell, "法庭") {
                room = roomText(value); minutes = nil
            } else if let value = labelled(cell, "聆案官") ?? labelled(cell, "裁判官") {
                judge = chinesePart(value)
            } else if isRoomCell(cell) {
                room = roomText(cell); minutes = nil
            } else if isJudgeCell(cell) {
                judge = chinesePart(cell)
            }
        }
    }

    /// `法庭 : 第42庭 (2字樓)` → `第42庭 (2字樓)`；冇冒號或冒號後面係空就 `nil`。
    private static func labelled(_ cell: String, _ label: String) -> String? {
        guard cell.hasPrefix(label), let colon = cell.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }
        let value = cell[cell.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func isCaseHeader(_ text: String) -> Bool {
        if ["案件編號", "案件號碼", "申索編號", "申索编號"].contains(where: text.contains) { return true }
        let lower = text.lowercased()
        return lower.contains("case no") || lower.contains("claim no")
    }

    private static func column(for text: String) -> Column? {
        if isCaseHeader(text) { return .caseNo }
        if text.contains("時間") { return .time }
        if ["法官", "聆案官", "裁判官", "審裁", "驗屍官", "司法"].contains(where: text.contains) { return .judge }
        if text.contains("法庭") || text.contains("法院") { return .court }
        if text.contains("性質") || text.contains("控罪") { return .nature }
        return nil
    }

    /// 性質／控罪格只留中文頭一段，太長或者似句子（備註）就唔要。
    private static func natureText(_ text: String?) -> String? {
        guard let text else { return nil }
        let zh = chinesePart(text)
        guard !zh.isEmpty, zh.count <= 24 else { return nil }
        return zh
    }

    private static func isTimeCell(_ text: String) -> Bool {
        text.count < 80 && firstMatch(timeCellPattern, in: text) != nil
    }

    private static func isCaseCell(_ text: String) -> Bool {
        text.count < 80 && firstMatch(caseNoPattern, in: text) != nil
    }

    private static func isRoomCell(_ text: String) -> Bool {
        firstMatch(roomPattern, in: text) != nil
    }

    private static func isJudgeCell(_ text: String) -> Bool {
        guard text.count < 120, !text.hasPrefix("日期"), !text.contains("案件表") else { return false }
        // 備註格都可能提到「法官」：只認短嘅中文部分，而且唔含句子標點
        let zh = chinesePart(text)
        guard zh.count <= 40, !zh.contains(where: { "，。；、".contains($0) }) else { return false }
        return ["法官", "聆案官", "審裁官", "裁判官", "審裁處成員"].contains(where: zh.contains)
    }

    private static func roomText(_ text: String) -> String {
        chinesePart(text)
    }

    /// 雙語儲存格只留中文部分：`第 5 庭 2 字樓 Court No.5 (2/F)` → `第 5 庭 2 字樓`。
    static func chinesePart(_ text: String) -> String {
        guard let range = text.range(of: "\\s(?:\\d+\\s+[A-Za-z]|\\d+(?:st|nd|rd|th)\\b|[A-Za-z])", options: .regularExpression) else { return text }
        let cut = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? text : cut
    }

    /// 案件編號格有時夾住備註（死因庭：`CCDI-269/2022(MC) [5/7]# 沒有陪審員…`），只留案號；合併案件（多個案號）唔拆。
    static func trimCaseNo(_ text: String) -> String {
        matches(caseIdentifierPattern, in: text).joined(separator: " ")
    }

    private static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static let timeCellPattern = try! NSRegularExpression(
        pattern: "^(?:不早於)?(?:上午|下午)?\\s*(?:Not before\\s*)?(?:\\d{1,2}\\s*[:：]\\s*\\d{2}|\\d{1,2}\\s*時)",
        options: .caseInsensitive
    )
    private static let caseNoPattern = try! NSRegularExpression(pattern: "[A-Z]{2,}[\\s-]*\\d+/\\d{4}")
    private static let roomPattern = try! NSRegularExpression(pattern: "^第\\s*\\d+\\s*(?:法)?庭")
    private static let caseIdentifierPattern = try! NSRegularExpression(
        pattern: "[A-Z]{2,}[\\s-]*\\d+/\\d{4}(?:\\([A-Z]+\\))?(?:\\s*\\[\\d+/\\d+(?:\\+\\d+)?\\]#*)?"
    )

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

    /// 要睇邊日嘅案件表：18:30 後（案件表大約嗰陣公布下一個工作天）轉去下一個工作天；週末同公眾假期（`holidays`，`yyyyMMdd`）跳過。
    static func listDate(now: Date, holidays: Set<String> = [], calendar: Calendar = ICalendar.hongKong) -> Date {
        var day = calendar.startOfDay(for: now)
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if minute >= 18 * 60 + 30 { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        // 最多跳 30 日，免得假期資料有問題時死循環
        for _ in 0..<30 where [1, 7].contains(calendar.component(.weekday, from: day)) || holidays.contains(PublicHolidays.key(day, calendar: calendar)) {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return day
    }

    /// `26102026`（DDMMYYYY）。
    static func dateCode(_ day: Date, calendar: Calendar = ICalendar.hongKong) -> String {
        let parts = calendar.dateComponents([.day, .month, .year], from: day)
        return String(format: "%02d%02d%04d", parts.day ?? 0, parts.month ?? 0, parts.year ?? 0)
    }

    static func isoDate(_ day: Date, calendar: Calendar = ICalendar.hongKong) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromISO value: String, calendar: Calendar = ICalendar.hongKong) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              isoDate(date, calendar: calendar) == value else { return nil }
        return date
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

    private static func fetch(_ url: URL, timeout: TimeInterval) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://e-services.judiciary.hk/dcl/index.jsp?lang=tc", forHTTPHeaderField: "Referer")
        request.setValue("zh-HK,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 4_000_000 else {
            throw URLError(.badServerResponse)
        }
        return decode(data)
    }

    /// 優先 UTF-8；網站如果改用 Big5-HKSCS 就轉碼，最後先用寬鬆 UTF-8。
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))
        return String(data: data, encoding: big5) ?? String(decoding: data, as: UTF8.self)
    }

    static let sourceNotice = "只顯示公開網頁中已解析的排期；附件、批量案件或未識別內容可能未列出。並非完整出庭紀錄，請以司法機構原頁及附件為準。不顯示訴訟各方。"

    enum LoadError: Error { case unrecognizedPage, mismatchedDate }

    static func document(_ html: String, code: String, day: Date, fetchedAt: Date) throws -> CourtDay {
        let excluded = try! NSRegularExpression(pattern: "<!--.*?-->|<(script|style)\\b[^>]*>.*?</\\1>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let content = replace(excluded, in: html, with: "")
        // 只驗證明確標示嘅案件表日期，唔用案件行或頁尾日期推斷。
        let labelledDate = try! NSRegularExpression(pattern: "(?:案件表日期|聆訊日期|Hearing Date|List Date)\\s*[:：]?\\s*(\\d{1,2})[/-](\\d{1,2})[/-](\\d{4})", options: .caseInsensitive)
        let text = cleanText(content)
        if let match = firstMatch(labelledDate, in: text) {
            let ns = text as NSString
            let sourceCode = String(format: "%02d%02d%04d", Int(ns.substring(with: match.range(at: 1))) ?? 0,
                                    Int(ns.substring(with: match.range(at: 2))) ?? 0, Int(ns.substring(with: match.range(at: 3))) ?? 0)
            guard sourceCode == dateCode(day) else { throw LoadError.mismatchedDate }
        }
        let cases = parse(content)
        let noListStatements: Set<String> = [
            "沒有案件表", "未有案件表", "暫無案件表", "沒有此日期的案件表", "此日期並無案件表", "找不到案件表",
            "no court list", "no court list available", "no daily cause list available"
        ]
        let messages = try! NSRegularExpression(pattern: "<(p|div|td|th|center|body)\\b[^>]*>[^<]+</\\1>", options: .caseInsensitive)
        let explicitNoList = matches(messages, in: content).contains {
            noListStatements.contains(cleanText($0).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "。.!！ ")))
        }
        guard !cases.isEmpty || explicitNoList else { throw LoadError.unrecognizedPage }
        return CourtDay(code: code, dateCode: dateCode(day), total: cases.count, cases: cases,
                        metadata: CourtMetadata(source: cases.isEmpty ? .officialNoList : .parsed,
                                                fetchedAt: fetchedAt, attemptedAt: fetchedAt))
    }

    static func failed(_ cached: CourtDay, message: String, at now: Date) -> CourtDay {
        var result = cached
        result.error = true
        result.metadata.failure = message
        result.metadata.attemptedAt = now
        return result
    }

    /// 完整案件表存檔，唔再讀取舊版已截斷嘅 UserDefaults 快取。
    static func load(code: String, day: Date, now: Date, forceReload: Bool = false, timeout: TimeInterval = 12) async -> CourtDay {
        let saved = cached(code: code, day: day)
        if !forceReload, !saved.error, !saved.metadata.isStale(at: now) { return saved }
        guard !Task.isCancelled, timeout > 0 else {
            return failed(saved, message: "本次更新未完成", at: now)
        }
        // 開始請求就記低輪次；即使首次失敗、逾時或 extension 被終止，下次亦會輪到其他法院。
        var attempted = saved
        attempted.metadata.attemptedAt = Date()
        try? CourtFileCache.save(attempted)
        do {
            guard CourtCatalog.all.contains(where: { $0.code == code }), let url = url(code: code, dateCode: dateCode(day)) else {
                throw URLError(.badURL)
            }
            let html = try await fetch(url, timeout: timeout)
            try Task.checkCancellation()
            let result = try document(html, code: code, day: day, fetchedAt: Date())
            try Task.checkCancellation()
            try? CourtFileCache.save(result)
            return result
        } catch {
            let message: String
            switch error {
            case LoadError.unrecognizedPage: message = "未能識別案件表；請查看官方原頁及附件"
            case LoadError.mismatchedDate: message = "來源案件表日期不符；未套用其他日期資料"
            default: message = Task.isCancelled ? "更新已取消" : "未能讀取官方案件表，請稍後重試"
            }
            let result = failed(attempted, message: message, at: attempted.metadata.attemptedAt ?? now)
            if !Task.isCancelled { try? CourtFileCache.save(result) }
            return result
        }
    }

    static func cached(code: String, day: Date) -> CourtDay {
        let dateCode = dateCode(day)
        return CourtFileCache.load(code: code, dateCode: dateCode)
            ?? CourtDay(code: code, dateCode: dateCode, total: 0, cases: [], error: true,
                        metadata: CourtMetadata(source: .unavailable, failure: "未取得此日期的案件表"))
    }

    /// 未嘗試嘅法院先行，其後按最後成功／嘗試時間排序；失敗亦消耗一輪，避免反覆重試而餓死後排。
    /// 可見法院優先，但每三個位置留一個畀其他法院；可見頁全數卡住亦有背景請求可以推進。
    static func loadOrder(cached: [CourtDay], visibleCodes: [String] = []) -> [Int] {
        let visible = Set(visibleCodes)
        let fair = cached.indices.sorted { lhs, rhs in
            func servicedAt(_ index: Int) -> Date {
                let metadata = cached[index].metadata
                return max(metadata.fetchedAt ?? .distantPast, metadata.attemptedAt ?? .distantPast)
            }
            let a = servicedAt(lhs), b = servicedAt(rhs)
            return a == b ? lhs < rhs : a < b
        }
        let priority = fair.filter { visible.contains(cached[$0].code) }
        let background = fair.filter { !visible.contains(cached[$0].code) }
        var result: [Int] = []
        var front = 0, back = 0
        while front < priority.count || back < background.count {
            for _ in 0..<2 where front < priority.count {
                result.append(priority[front])
                front += 1
            }
            if back < background.count {
                result.append(background[back])
                back += 1
            }
        }
        return result
    }

    /// 最多三個請求；逐個回報，但輸出仍按原有選擇順序。timeout 係整批實際時間，唔係連線閒置上限。
    static func loadAll(codes: [String], day: Date, now: Date, forceReload: Bool = false,
                        timeout: TimeInterval? = nil, visibleCodes: [String] = [],
                        onLoaded: (@Sendable (CourtDay) async -> Void)? = nil) async -> [CourtDay] {
        let saved = CourtCatalog.selection(codes).map { cached(code: $0, day: day) }
        return await loadAll(cached: saved, now: now, timeout: timeout, visibleCodes: visibleCodes, onLoaded: onLoaded) { code in
            await load(code: code, day: day, now: now, forceReload: forceReload)
        }
    }

    /// 可注入支援取消嘅 loader，離線測試排隊／逾時；正式使用 URLSession.data(for:) 隨 task 取消請求。
    static func loadAll(cached: [CourtDay], now: Date, timeout: TimeInterval? = nil, visibleCodes: [String] = [],
                        onLoaded: (@Sendable (CourtDay) async -> Void)? = nil,
                        loader: @escaping @Sendable (String) async -> CourtDay) async -> [CourtDay] {
        let clock = ContinuousClock()
        let deadline = timeout.map { clock.now.advanced(by: .seconds(max(0, $0))) }
        let order = loadOrder(cached: cached, visibleCodes: visibleCodes)
        // 獨立計時 task 取消整個 worker，唔使等 onLoaded 返回先取消在途 URLSession 請求。
        return await withTaskGroup(of: [CourtDay]?.self) { race in
            race.addTask {
                await withTaskGroup(of: (Int, CourtDay).self) { group in
                    var next = 0
                    var results: [Int: CourtDay] = [:]
                    func canEnqueue() -> Bool {
                        !Task.isCancelled && (deadline.map { clock.now < $0 } ?? true)
                    }
                    func enqueue(_ index: Int) {
                        group.addTask { (index, await loader(cached[index].code)) }
                    }
                    while next < min(3, order.count), canEnqueue() {
                        enqueue(order[next])
                        next += 1
                    }
                    for await (index, result) in group {
                        results[index] = result
                        if !Task.isCancelled { await onLoaded?(result) }
                        if next < order.count, canEnqueue() {
                            enqueue(order[next])
                            next += 1
                        }
                    }
                    return cached.indices.map { index in
                        results[index] ?? failed(cached[index], message: "本次更新未完成", at: now)
                    }
                }
            }
            if let deadline {
                race.addTask {
                    try? await clock.sleep(until: deadline)
                    return nil
                }
            }
            while let result = await race.next() {
                // 正常完成亦要取消 timer，唔可以等足剩餘 deadline 先離開 task group。
                race.cancelAll()
                if let result { return result }
            }
            return cached
        }
    }
}

/// App 同 extension 各自沙盒嘅完整快取；唔需要改 App Group 設定。
enum CourtFileCache {
    static var directory: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("CourtSchedules-v1", isDirectory: true)
    }

    private static func file(code: String, dateCode: String, directory: URL) -> URL? {
        guard CourtCatalog.all.contains(where: { $0.code == code }), dateCode.count == 8,
              dateCode.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return directory.appendingPathComponent("\(code)-\(dateCode).json")
    }

    private static func isCacheable(_ value: CourtDay) -> Bool {
        value.total == value.cases.count && (value.metadata.fetchedAt != nil
            || (value.error && value.metadata.source == .unavailable && value.cases.isEmpty && value.metadata.attemptedAt != nil))
    }

    static func load(code: String, dateCode: String, directory: URL = Self.directory) -> CourtDay? {
        guard let file = file(code: code, dateCode: dateCode, directory: directory),
              let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(CourtDay.self, from: data),
              value.code == code, value.dateCode == dateCode, isCacheable(value) else { return nil }
        return value
    }

    static func save(_ value: CourtDay, directory: URL = Self.directory) throws {
        guard let file = file(code: value.code, dateCode: value.dateCode, directory: directory),
              isCacheable(value) else { throw URLError(.cannotWriteToFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
    }
}
