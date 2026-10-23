import Foundation

struct SchoolDay {
    var cycle: [String]
    var items: [CalendarOccurrence]
}

/// 更份同學校日曆嘅原始資料；每個 entry 再按自己嘅時間計今日、明日。
/// 每個來源各自有逾時同快取：一個慢或者失敗，唔會拖累其他。
struct ScheduleData {
    var roster: Roster?
    var basic: [String: DutyTime]
    var cards: [String: DutyCard]
    var sheets: [DutySheet]
    var places: PlaceNames
    var events: [CalendarEvent]
    var configured: Bool
    var rosterFailed: Bool
    /// 讀唔到（而且冇快取）嘅學校日曆名
    var schoolFailed: [String]

    static let empty = ScheduleData(
        roster: nil, basic: [:], cards: [:], sheets: [], places: .empty, events: [],
        configured: false, rosterFailed: false, schoolFailed: []
    )

    static func cached(token: String?) -> ScheduleData {
        ScheduleData(
            roster: DataCache.load(Roster.self, key: "roster"),
            basic: DataCache.load([String: DutyTime].self, key: "duties") ?? [:],
            cards: DataCache.load([String: DutyCard].self, key: "dutyCards") ?? [:],
            sheets: DataCache.load([DutySheet].self, key: "dutySheets") ?? [],
            places: DataCache.load(PlaceNames.self, key: "places") ?? .empty,
            events: SchoolCalendars.sources.flatMap { DataCache.load([CalendarEvent].self, key: schoolKey($0)) ?? [] },
            configured: RosterAPI.cleanToken(token) != nil,
            rosterFailed: false,
            schoolFailed: []
        )
    }

    static func load(token: String?, now: Date) async -> ScheduleData {
        async let roster = withDeadline(12, fallback: (DataCache.load(Roster.self, key: "roster"), true)) {
            await loadRoster(token: token)
        }
        async let basic = withDeadline(12, fallback: DataCache.load([String: DutyTime].self, key: "duties") ?? [:]) {
            await loadBasic(now: now)
        }
        async let sheets = withDeadline(10, fallback: DataCache.load([DutySheet].self, key: "dutySheets") ?? []) {
            await loadSheets(now: now)
        }
        async let places = withDeadline(10, fallback: DataCache.load(PlaceNames.self, key: "places") ?? .empty) {
            await loadPlaces(now: now)
        }
        async let school = loadSchool(now: now)

        let (rosterResult, sheetList) = await (roster, sheets)
        let cards = await withDeadline(8, fallback: DataCache.load([String: DutyCard].self, key: "dutyCards") ?? [:]) {
            await loadCards(roster: rosterResult.0, sheets: sheetList, now: now)
        }
        let schoolResult = await school
        return ScheduleData(
            roster: rosterResult.0,
            basic: await basic,
            cards: cards,
            sheets: sheetList,
            places: await places,
            events: schoolResult.events,
            configured: RosterAPI.cleanToken(token) != nil,
            rosterFailed: rosterResult.1,
            schoolFailed: schoolResult.failed
        )
    }

    // MARK: 更份

    private static func loadRoster(token: String?) async -> (Roster?, Bool) {
        guard let url = RosterAPI.url(token: token) else { return (nil, false) }
        do {
            let roster = try RosterAPI.parse(try await Fetcher.data(from: url, timeout: 10))
            DataCache.save(roster, key: "roster")
            return (roster, false)
        } catch {
            return (DataCache.load(Roster.self, key: "roster"), true)
        }
    }

    private static func loadBasic(now: Date) async -> [String: DutyTime] {
        if let fresh = DataCache.fresh([String: DutyTime].self, key: "duties", maxAge: 6 * 3_600, now: now), !fresh.isEmpty {
            return fresh
        }
        if let duties = try? DutyBasic.parse(try await Fetcher.firstData(from: DutyData.urls("data/duty-basic.json"), timeout: 10)),
           !duties.isEmpty {
            DataCache.save(duties, key: "duties", stamped: now)
            return duties
        }
        return DataCache.load([String: DutyTime].self, key: "duties") ?? [:]
    }

    private static func loadSheets(now: Date) async -> [DutySheet] {
        if let fresh = DataCache.fresh([DutySheet].self, key: "dutySheets", maxAge: 6 * 3_600, now: now), !fresh.isEmpty {
            return fresh
        }
        if let sheets = try? DutyData.parseIndex(try await Fetcher.firstData(from: DutyData.urls("data/duties/index.json"))),
           !sheets.isEmpty {
            DataCache.save(sheets, key: "dutySheets", stamped: now)
            return sheets
        }
        return DataCache.load([DutySheet].self, key: "dutySheets") ?? []
    }

    private static func loadPlaces(now: Date) async -> PlaceNames {
        if let fresh = DataCache.fresh(PlaceNames.self, key: "places", maxAge: 7 * 86_400, now: now) {
            return fresh
        }
        if let places = try? PlaceNames.parse(try await Fetcher.firstData(from: DutyData.urls("data/tml-network.json"))) {
            DataCache.save(places, key: "places", stamped: now)
            return places
        }
        return DataCache.load(PlaceNames.self, key: "places") ?? .empty
    }

    /// 今日同明日（服務日）用到嘅更份卡。快取有齊而且 12 小時內讀過就唔再下載 sheet。
    private static func loadCards(roster: Roster?, sheets: [DutySheet], now: Date) async -> [String: DutyCard] {
        let cached = DataCache.load([String: DutyCard].self, key: "dutyCards") ?? [:]
        guard let roster, !sheets.isEmpty else { return cached }
        let today = Days.serviceDate(now)
        var wanted: [String: Set<String>] = [:]
        for offset in 0...2 {
            guard let date = Days.add(today, offset), let code = roster.entry(on: date)?.code,
                  code.range(of: "^[0-9]{7}$", options: .regularExpression) != nil else { continue }
            wanted[DutyData.sheet(for: code, date: date, sheets: sheets), default: []].insert(code)
        }
        let keys = wanted.flatMap { sheet, ids in ids.map { DutyDay.cardKey(sheet: sheet, id: $0) } }
        let recent = DataCache.savedAt("dutyCards").map { now.timeIntervalSince($0) < 12 * 3_600 } ?? false
        if recent, keys.allSatisfy({ cached[$0] != nil }) { return cached }

        var result: [String: DutyCard] = [:]
        for (sheet, ids) in wanted {
            guard let file = sheets.first(where: { $0.code == sheet })?.file else { continue }
            if let data = try? await Fetcher.firstData(from: DutyData.urls("data/duties/\(file)"), timeout: 10),
               let cards = try? DutyData.parseCards(data, ids: ids) {
                for (id, card) in cards { result[DutyDay.cardKey(sheet: sheet, id: id)] = card }
            } else {
                for id in ids { result[DutyDay.cardKey(sheet: sheet, id: id)] = cached[DutyDay.cardKey(sheet: sheet, id: id)] }
            }
        }
        DataCache.save(result, key: "dutyCards", stamped: now)
        return result
    }

    // MARK: 學校日曆

    private static func schoolKey(_ source: SchoolCalendars.Source) -> String { "school.\(source.name)" }

    /// 每個日曆各自讀、各自快取（3 小時內讀過就唔再讀）。讀唔到又冇快取先當失敗。
    private static func loadSchool(now: Date) async -> (events: [CalendarEvent], failed: [String]) {
        await withTaskGroup(of: (String, [CalendarEvent]?).self) { group in
            for source in SchoolCalendars.sources {
                group.addTask {
                    let key = schoolKey(source)
                    if let fresh = DataCache.fresh([CalendarEvent].self, key: key, maxAge: 3 * 3_600, now: now) {
                        return (source.name, fresh)
                    }
                    let fetched: [CalendarEvent]? = await withDeadline(15, fallback: nil) {
                        guard let url = SchoolCalendars.url(source),
                              let data = try? await Fetcher.data(from: url, timeout: 12),
                              let text = String(data: data, encoding: .utf8), text.contains("BEGIN:VCALENDAR") else { return nil }
                        return ICalendar.relevant(ICalendar.parse(text, calendar: source.name), around: now)
                    }
                    if let fetched {
                        DataCache.save(fetched, key: key, stamped: now)
                        return (source.name, fetched)
                    }
                    return (source.name, DataCache.load([CalendarEvent].self, key: key))
                }
            }
            var events: [CalendarEvent] = []
            var failed: [String] = []
            for await (name, result) in group {
                if let result { events += result } else { failed.append(name) }
            }
            return (events, failed.sorted())
        }
    }

    // MARK: 某日

    func duty(on serviceDate: String) -> DutyDay? {
        roster.flatMap { DutyDay.make(roster: $0, date: serviceDate, basic: basic, cards: cards, sheets: sheets, places: places) }
    }

    /// 今日唔使返工或者已經放工：之後 14 日內第一個有上班時間嘅更。
    func nextDuty(after serviceDate: String) -> DutyDay? {
        for offset in 1...14 {
            guard let date = Days.add(serviceDate, offset), let day = duty(on: date) else { continue }
            if day.on != nil { return day }
        }
        return nil
    }

    func school(dayStart: Date) -> SchoolDay {
        let items = ICalendar.occurrences(of: events, onDayStarting: dayStart)
        return SchoolDay(
            cycle: items.filter { $0.calendar == SchoolCalendars.cycleName }.map(\.title),
            items: items.filter { $0.calendar != SchoolCalendars.cycleName }
        )
    }
}

/// 逾時就用 fallback，唔令 widget 卡住。
func withDeadline<T: Sendable>(_ seconds: Double, fallback: T, operation: @escaping @Sendable () async -> T) async -> T {
    await withTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return fallback
        }
        let first = await group.next() ?? fallback
        group.cancelAll()
        return first
    }
}
