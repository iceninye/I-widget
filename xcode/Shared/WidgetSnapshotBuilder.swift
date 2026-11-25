import Foundation

enum WidgetSnapshotBuilder {
    static func build(
        entry: OverviewEntry,
        courts: [CourtDay] = [],
        listDate: Date? = nil,
        now: Date = Date()
    ) -> WidgetExport {
        let calendar = ICalendar.hongKong
        let stats = entry.stats
        let uptime = stats.uptime(at: now)
        let info = entry.info
        let schedule = entry.schedule

        let minute = listDate.flatMap { CourtList.minuteOfDay(now: now, listDate: $0) }
        return WidgetExport(
            schemaVersion: WidgetSchema.version,
            generatedAt: now,
            serviceDate: exportDateCode(entry.serviceToday),
            theme: entry.theme.rawValue,
            freshness: WidgetFreshness(
                today: OverviewEntry.lastSuccess(info: info, schedule: schedule, part: .today),
                info: OverviewEntry.lastSuccess(info: info, schedule: schedule, part: .info),
                schedule: schedule.lastSuccessAt,
                weather: info.weather?.fetchedAt,
                warningsToday: info.warningsStamps[.today],
                warningsInfo: info.warningsStamps[.info],
                court: CourtList.lastSuccess(days: courts)
            ),
            system: WidgetSystem(
                capturedAt: now,
                battery: WidgetBattery(
                    level: stats.batteryLevel,
                    charging: stats.isCharging,
                    fullyCharged: stats.isFullyCharged,
                    lowPowerMode: stats.isLowPowerMode,
                    estimatedText: BatteryHistory.text(entry.battery) ?? "未有資料",
                    rateText: entry.batteryRate.map { String(format: "%.1f%% / 小時", $0) } ?? "估算中"
                ),
                storage: WidgetStorage(
                    freeBytes: stats.freeBytes,
                    totalBytes: stats.totalBytes,
                    freeText: Formatting.bytes(stats.freeBytes),
                    totalText: Formatting.bytes(stats.totalBytes),
                    usedText: Formatting.usedFraction(free: stats.freeBytes, total: stats.totalBytes)
                        .map(Formatting.percent) ?? Formatting.missing
                ),
                memory: WidgetMemory(
                    totalBytes: stats.memoryTotal,
                    availableBytes: stats.memoryAvailable,
                    lines: entry.memoryBack.map { WidgetLine(label: $0.label, value: $0.value) }
                ),
                uptimeSeconds: uptime,
                uptimeText: Formatting.uptime(uptime),
                bootAt: stats.bootDate,
                systemName: stats.systemName,
                systemVersion: stats.systemVersion,
                versionText: stats.versionText,
                latestOS: info.latestOS,
                osStatus: osStatusText(entry.osStatus)
            ),
            duty: WidgetDuty(
                configured: schedule.configured,
                failed: schedule.rosterFailed,
                today: entry.dutyToday.map { dutyDay($0, calendar: calendar) },
                tomorrow: entry.dutyTomorrow.map { dutyDay($0, calendar: calendar) },
                events: schedule.dutyEvents(now: now).prefix(8).map { event in
                    WidgetDutyEvent(
                        id: "\(event.kind.rawValue)-\(Int(event.at.timeIntervalSince1970.rounded()))",
                        action: event.action,
                        at: event.at,
                        displayAt: Formatting.clock(event.at, calendar: calendar),
                        title: event.title,
                        detail: event.detail,
                        place: event.place,
                        note: event.note
                    )
                },
                week: dutyWeek(entry: entry),
                shiftForecast: shiftForecast(entry: entry, now: now, calendar: calendar),
                weekText: entry.weekSummary?.text,
                nextHoliday: entry.nextHoliday.map {
                    WidgetHoliday(title: $0.title, rangeText: $0.rangeText, daysAway: $0.daysAway)
                },
                detailLines: entry.todayBack.map { WidgetLine(label: $0.label, value: $0.value) }
            ),
            school: WidgetSchool(
                failed: schedule.schoolFailed,
                today: schoolDay(entry.schoolToday),
                tomorrow: schoolDay(entry.schoolTomorrow)
            ),
            weather: weather(info.weather),
            warnings: WidgetWarnings(
                available: info.warnings != nil,
                items: (info.warnings ?? []).map { WidgetWarning(text: $0.text, severe: $0.severe) }
            ),
            train: WidgetTrain(
                available: info.train != nil,
                stateText: info.train?.state.text ?? "未有資料",
                message: info.train?.message ?? ""
            ),
            environment: WidgetEnvironment(
                sections: [
                    WidgetInfoSection(id: "uv", title: "紫外線", lines: entry.uvBack.map { WidgetLine(label: $0.label, value: $0.value) }),
                    WidgetInfoSection(id: "air", title: "空氣", lines: entry.airBack.map { WidgetLine(label: $0.label, value: $0.value) }),
                    WidgetInfoSection(id: "fx", title: "匯率", lines: entry.fxBack.map { WidgetLine(label: $0.label, value: $0.value) }),
                    WidgetInfoSection(id: "gold", title: "黃金", lines: entry.goldBack.map { WidgetLine(label: $0.label, value: $0.value) }),
                    WidgetInfoSection(id: "os", title: "系統", lines: entry.osBack.map { WidgetLine(label: $0.label, value: $0.value) }),
                ]
            ),
            vps: WidgetVPS(
                configured: entry.vps.configured,
                available: entry.vps.status != nil,
                failed: entry.vps.failed,
                lines: entry.vpsBack.map { WidgetLine(label: $0.label, value: $0.value) }
            ),
            courts: WidgetCourts(
                listDate: listDate,
                updatedAt: CourtList.lastSuccess(days: courts),
                items: courts.prefix(WidgetSchema.maxCourts).map { courtDay($0, minute: minute) }
            )
        )
    }

    private static func dutyWeek(entry: OverviewEntry) -> [WidgetDutyStripDay] {
        let weekdays = ["一", "二", "三", "四", "五", "六", "日"]
        return (0..<7).compactMap { offset in
            guard let sourceDate = Days.add(entry.serviceToday, offset) else { return nil }
            let day = entry.schedule.duty(on: sourceDate)
            let parts = sourceDate.split(separator: "-")
            return WidgetDutyStripDay(
                date: exportDateCode(sourceDate),
                weekday: Days.weekdayIndex(sourceDate).flatMap { weekdays.indices.contains($0) ? weekdays[$0] : nil } ?? "—",
                dayNumber: parts.last.map(String.init) ?? "—",
                label: day?.shortLabel ?? "—",
                tone: day.map(dutyTone) ?? "unknown",
                weather: entry.info.weather?.day(sourceDate).map(weatherDay)
            )
        }
    }

    private static func shiftForecast(entry: OverviewEntry, now: Date, calendar: Calendar) -> [WidgetShiftForecast] {
        guard let day = entry.dutyToday, let weather = entry.info.weather else { return [] }
        let moments: [(String, Int?)] = [("返工", day.on), ("放工", day.off)]
        return moments.compactMap { label, seconds in
            guard let seconds, let at = day.moment(atServiceSecond: seconds),
                  at > now.addingTimeInterval(-3_600),
                  let hour = weather.hour(at: at, calendar: calendar) else { return nil }
            return WidgetShiftForecast(
                label: "\(label) \(DutyDay.clock(seconds))",
                code: hour.code,
                symbol: hour.code.map(WeatherCode.symbol),
                tempText: Formatting.degrees(hour.temp),
                rainChance: hour.rainChance
            )
        }
    }

    private static func dutyTone(_ day: DutyDay) -> String {
        switch day.kind {
        case .rest: return "rest"
        case .leave: return "leave"
        case .pending: return "pending"
        case .spare: return day.shift?.rawValue ?? "spare"
        case .other: return day.shift?.rawValue ?? "other"
        case .duty: return day.shift?.rawValue ?? "duty"
        }
    }

    private static func dutyDay(_ day: DutyDay, calendar: Calendar) -> WidgetDutyDay {
        WidgetDutyDay(
            date: exportDateCode(day.date),
            code: day.code,
            title: day.title,
            group: day.group,
            datedSheet: day.datedSheet,
            isOverride: day.isOverride,
            tone: dutyTone(day),
            times: day.times,
            route: day.route,
            mealText: day.mealText,
            hoursText: day.hoursText,
            hint: day.hint,
            onAt: day.on.flatMap { day.moment(atServiceSecond: $0) },
            offAt: day.off.flatMap { day.moment(atServiceSecond: $0) }
        )
    }

    private static func schoolDay(_ day: SchoolDay) -> WidgetSchoolDay {
        WidgetSchoolDay(
            cycle: day.cycle,
            items: day.items.map {
                WidgetSchoolItem(title: $0.title, start: $0.start, end: $0.end, allDay: $0.allDay)
            }
        )
    }

    private static func weather(_ snapshot: WeatherSnapshot?) -> WidgetWeather {
        guard let snapshot else {
            return WidgetWeather(
                available: false, fetchedAt: nil, currentTemp: nil,
                today: nil, tomorrow: nil, daily: []
            )
        }
        return WidgetWeather(
            available: true,
            fetchedAt: snapshot.fetchedAt,
            currentTemp: snapshot.currentTemp,
            today: weatherDay(snapshot.today),
            tomorrow: snapshot.tomorrow.map(weatherDay),
            daily: Array(snapshot.days ?? []).prefix(7).map {
                WidgetDatedWeather(date: exportDateCode($0.date), day: weatherDay($0.day))
            }
        )
    }

    private static func weatherDay(_ day: WeatherDay) -> WidgetWeatherDay {
        WidgetWeatherDay(
            code: day.code,
            codeText: WeatherCode.text(day.code),
            symbol: WeatherCode.symbol(day.code),
            minTemp: day.minTemp,
            maxTemp: day.maxTemp,
            tempText: Formatting.tempRange(day),
            rainChance: day.rainChance,
            uvIndex: day.uvIndex
        )
    }

    private static func courtDay(_ day: CourtDay, minute: Int?) -> WidgetCourtDay {
        let relevant = day.upcoming(afterMinute: minute)
        let shown = relevant.prefix(WidgetSchema.maxCasesPerCourt)
        return WidgetCourtDay(
            code: day.code,
            name: day.name,
            dateCode: exportDateCode(day.dateCode),
            fetchedAt: day.fetchedAt,
            error: day.error,
            total: day.total,
            truncated: relevant.count > WidgetSchema.maxCasesPerCourt,
            categories: day.categoryCounts.map {
                WidgetCategoryCount(category: $0.category.rawValue, categoryTitle: $0.category.title, count: $0.count)
            },
            deepLink: CourtLink(code: day.code).url.absoluteString,
            cases: shown.map { item in
                let type = item.caseType
                return WidgetCourtCase(
                    room: item.room,
                    judge: item.judge,
                    minutes: item.minutes,
                    timeText: item.timeText,
                    caseNo: item.caseNo,
                    nature: item.nature,
                    offence: item.offence,
                    category: type.category.rawValue,
                    categoryTitle: type.category.title,
                    detailText: item.detailText,
                    deepLink: item.link(code: day.code).url.absoluteString
                )
            }
        )
    }

    /// 更份／天氣用 YYYY-MM-DD，法院用 DDMMYYYY；跨 app schema 統一轉做 YYYYMMDD。
    static func exportDateCode(_ value: String) -> String {
        let dashed = value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        let normalized = dashed ? value.replacingOccurrences(of: "-", with: "") : value
        guard normalized.count == 8, normalized.allSatisfy(\.isNumber) else { return value }

        let year = Int(normalized.suffix(4))
        let firstMonth = Int(normalized.dropFirst(4).prefix(2))
        let firstDay = Int(normalized.suffix(2))
        if (2000...2100).contains(Int(normalized.prefix(4)) ?? 0),
           (1...12).contains(firstMonth ?? 0), (1...31).contains(firstDay ?? 0) {
            return normalized
        }

        let day = Int(normalized.prefix(2))
        let month = Int(normalized.dropFirst(2).prefix(2))
        guard (1...31).contains(day ?? 0), (1...12).contains(month ?? 0),
              (2000...2100).contains(year ?? 0) else { return value }
        return String(normalized.suffix(4))
            + String(normalized.dropFirst(2).prefix(2))
            + String(normalized.prefix(2))
    }

    private static func osStatusText(_ status: OSVersionStatus) -> String {
        switch status {
        case .unknown: return "unknown"
        case .upToDate: return "upToDate"
        case .updateAvailable: return "updateAvailable"
        }
    }
}
