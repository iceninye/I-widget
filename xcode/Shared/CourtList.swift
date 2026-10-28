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

    private typealias Fields = (room: String?, judge: String?, time: String?, caseNo: String?)

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
            var positional = false
            if columns[.caseNo] != nil, raw.count == headerCount {
                func at(_ column: Column) -> String? {
                    guard let index = columns[column], index < raw.count, !raw[index].isEmpty else { return nil }
                    return raw[index]
                }
                fields = (at(.court), at(.judge), at(.time), at(.caseNo))
                positional = true
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
            guard let caseNo = fields.caseNo, !positional || caseNo.contains(where: \.isNumber) else { continue }
            cases.append(CourtCase(room: room, judge: judge, minutes: minutes, caseNo: trimCaseNo(caseNo)))
        }
        return cases
    }

    /// 格數唔齊（合併儲存格）嘅行：按內容認出時間、案件編號，必要時法庭同法官。
    private static func classify(_ cells: [String], expectRoom: Bool, expectJudge: Bool) -> Fields {
        var result: Fields = (nil, nil, nil, nil)
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
        return nil
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
        guard let match = caseTrailPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let rest = Range(match.range(at: 2), in: text), let head = Range(match.range(at: 1), in: text),
              firstMatch(caseNoPattern, in: String(text[rest])) == nil else { return text }
        return String(text[head])
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
    private static let caseTrailPattern = try! NSRegularExpression(
        pattern: "^(.*?[A-Z]{2,}[\\s-]*\\d+/\\d{4}(?:\\([A-Z]+\\))?(?:\\s*\\[\\d+/\\d+(?:\\+\\d+)?\\]#*)?)\\s+(\\S.*)$"
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
        return decode(data)
    }

    /// 優先 UTF-8；網站如果改用 Big5-HKSCS 就轉碼，最後先用寬鬆 UTF-8。
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))
        return String(data: data, encoding: big5) ?? String(decoding: data, as: UTF8.self)
    }

    private static func cacheKey(_ code: String, _ dateCode: String) -> String { "court.\(code).\(dateCode)" }

    /// 10 分鐘內嘅快取直接用；讀取失敗就用舊快取，冇快取先標記 error。
    static func load(code: String, day: Date, now: Date) async -> CourtDay {
        let dateCode = dateCode(day)
        let key = cacheKey(code, dateCode)
        let cached = DataCache.load(CourtDay.self, key: key)
        // 空結果（未公布或解析唔到）只信 3 分鐘，之後會再試
        let maxAge: TimeInterval = (cached?.total ?? 0) == 0 ? 3 * 60 : 10 * 60
        if let fresh = DataCache.fresh(CourtDay.self, key: key, maxAge: maxAge, now: now) { return fresh }
        if let url = url(code: code, dateCode: dateCode), let html = try? await fetch(url) {
            let cases = parse(html)
            let result = CourtDay(code: code, dateCode: dateCode, total: cases.count, cases: Array(cases.prefix(300)))
            // 今次空但之前有資料：保留舊嘅，唔好蓋走
            if cases.isEmpty, let cached, cached.total > 0 { return cached }
            DataCache.save(result, key: key, stamped: now)
            return result
        }
        return cached ?? CourtDay(code: code, dateCode: dateCode, total: 0, cases: [], error: true)
    }

    static func cached(code: String, day: Date) -> CourtDay {
        let dateCode = dateCode(day)
        return DataCache.load(CourtDay.self, key: cacheKey(code, dateCode)) ?? CourtDay(code: code, dateCode: dateCode, total: 0, cases: [], error: true)
    }

    /// 同時最多 `limit` 個請求，對網站同電量都友善啲。
    static func loadAll(codes: [String], day: Date, now: Date, limit: Int = 3) async -> [CourtDay] {
        await withTaskGroup(of: (Int, CourtDay).self) { group in
            var results: [(Int, CourtDay)] = []
            var next = 0
            func addNext() {
                guard next < codes.count else { return }
                let (index, code) = (next, codes[next])
                next += 1
                group.addTask { (index, await load(code: code, day: day, now: now)) }
            }
            for _ in 0..<min(limit, codes.count) { addNext() }
            for await item in group {
                results.append(item)
                addNext()
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
