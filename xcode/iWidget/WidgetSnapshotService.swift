import Foundation

enum WidgetSnapshotService {
    static func load(now: Date = Date(), force: Bool = false) async -> OverviewEntry {
        let roster = AppSettings.string(AppSettings.rosterToken)
        let url = AppSettings.string(AppSettings.statusURL)
        let token = AppSettings.string(AppSettings.vpsToken)
        async let info = withDeadline(20, fallback: ExtraInfo.cached(now: now)) {
            await ExtraInfo.load(now: now, warningScopes: [.today, .info], force: force)
        }
        async let schedule = ScheduleData.load(token: roster, now: now, force: force)
        async let vps = VPSState.load(url: url, token: token, now: now, force: force)
        let loaded = await (info, schedule, vps)
        let stats = await SystemStats.read()
        let battery = batteryReading(stats: stats, now: now)
        let entry = OverviewEntry(
            date: now,
            stats: stats,
            battery: battery.estimate,
            info: loaded.0,
            schedule: loaded.1,
            vps: loaded.2,
            updatedAt: OverviewEntry.lastSuccess(info: loaded.0, schedule: loaded.1),
            batteryRate: battery.rate,
            theme: AppSettings.loadScriptableTheme()
        )

        return entry
    }

    static func loadCourts(now: Date = Date(), force: Bool = false) async -> (days: [CourtDay], listDate: Date?) {
        let codes = courtCodes()
        guard !codes.isEmpty else { return ([], nil) }
        let holidays = await withDeadline(12, fallback: PublicHolidays.cached()) {
            await PublicHolidays.load(now: now)
        }
        let day = CourtList.listDate(now: now, holidays: holidays)
        let cached = codes.map { CourtList.cached(code: $0, day: day) }
        let days = await withDeadline(20, fallback: cached) {
            await CourtList.loadAll(codes: codes, day: day, now: now, holidays: holidays, force: force)
        }
        return (days, day)
    }

    static func export(now: Date = Date()) async -> WidgetExport {
        async let loaded = load(now: now)
        async let courts = loadCourts(now: now)
        let (loadedEntry, courtData) = await (loaded, courts)
        return WidgetSnapshotBuilder.build(
            entry: loadedEntry,
            courts: courtData.days,
            listDate: courtData.listDate,
            now: now
        )
    }

    static func courtCodes() -> [String] {
        let raw = UserDefaults.standard.string(forKey: "court.codes") ?? "DC,ALLMAG,CFA"
        return CourtCatalog.selected(raw, limit: WidgetSchema.maxCourts)
    }

    private static func batteryReading(stats: SystemStats, now: Date) -> (estimate: BatteryEstimate, rate: Double?) {
        var history = DataCache.load([BatterySample].self, key: "batteryHistory") ?? []
        if let level = stats.batteryLevel {
            let sample = BatterySample(
                time: now,
                level: level,
                charging: stats.isCharging || stats.isFullyCharged
            )
            history = BatteryHistory.appending(sample, to: history)
            DataCache.save(history, key: "batteryHistory")
        }
        let rate = BatteryHistory.percentPerHour(history, now: now)
        if stats.isFullyCharged { return (.full, rate) }
        return (BatteryHistory.estimate(history, now: now), rate)
    }
}
