import Foundation

/// 資料格背面：多啲資料，每行「標籤 + 內容」。
struct BackLine: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

extension OverviewEntry {
    private func clock(_ date: Date?) -> String { date.map { Formatting.clock($0) } ?? Formatting.missing }

    private func monthDayClock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0) \(Formatting.clock(date))"
    }

    var batteryBack: [BackLine] {
        var lines = [BackLine(
            label: "狀態",
            value: (stats.isFullyCharged ? "已充滿" : stats.isCharging ? "充電中" : "使用電池") + (stats.isLowPowerMode ? " · 低耗電" : "")
        )]
        if let rate = batteryRate {
            lines.append(BackLine(label: stats.isCharging ? "充電速度" : "耗電速度", value: String(format: "%.1f%% / 小時", rate)))
        } else {
            lines.append(BackLine(label: "速度", value: "估算中"))
        }
        lines.append(BackLine(label: "預計", value: BatteryHistory.text(battery) ?? Formatting.missing))
        return lines
    }

    var storageBack: [BackLine] {
        let used = Formatting.usedFraction(free: stats.freeBytes, total: stats.totalBytes)
        return [
            BackLine(label: "已用", value: used.map { Formatting.percent($0) } ?? Formatting.missing),
            BackLine(label: "可用", value: Formatting.bytes(stats.freeBytes)),
            BackLine(label: "總共", value: Formatting.bytes(stats.totalBytes)),
        ]
    }

    var uptimeBack: [BackLine] {
        let uptime = stats.uptime(at: date)
        let untilDue = uptime.map { RebootHint.dueAfter - $0 }
        let advice: String
        if let untilDue, untilDue > 0 {
            advice = "仲有 \(Formatting.uptime(untilDue))"
        } else if untilDue != nil {
            advice = "已超過 7 日"
        } else {
            advice = Formatting.missing
        }
        return [
            BackLine(label: "開機於", value: stats.bootDate.map(monthDayClock) ?? Formatting.missing),
            BackLine(label: "已開機", value: Formatting.uptime(uptime)),
            BackLine(label: "建議重啟", value: advice),
        ]
    }

    var weatherBack: [BackLine] {
        guard let weather = info.weather else { return [BackLine(label: "天氣", value: "未有資料")] }
        func line(_ label: String, _ day: WeatherDay?) -> BackLine {
            guard let day else { return BackLine(label: label, value: Formatting.missing) }
            let rain = day.rainChance.map { " · 雨 \($0)%" } ?? ""
            return BackLine(label: label, value: "\(WeatherCode.text(day.code)) \(Formatting.tempRange(day))\(rain)")
        }
        return [line("今日", weather.today), line("明日", weather.tomorrow), BackLine(label: "更新", value: clock(weather.fetchedAt))]
    }

    var uvBack: [BackLine] {
        guard let weather = info.weather else { return [BackLine(label: "紫外線", value: "未有資料")] }
        func uv(_ day: WeatherDay?) -> String {
            guard let value = day?.uvIndex else { return Formatting.missing }
            return "\(Int(value.rounded())) \(UVLevel.text(value))"
        }
        func rain(_ day: WeatherDay?) -> String { day?.rainChance.map { "\($0)%" } ?? Formatting.missing }
        return [
            BackLine(label: "今日", value: "UV \(uv(weather.today)) · 雨 \(rain(weather.today))"),
            BackLine(label: "明日", value: "UV \(uv(weather.tomorrow)) · 雨 \(rain(weather.tomorrow))"),
            BackLine(label: "更新", value: clock(weather.fetchedAt)),
        ]
    }

    var airBack: [BackLine] {
        guard let air = info.air else { return [BackLine(label: "空氣", value: "未有資料")] }
        return [
            BackLine(label: "US AQI", value: "\(air.aqi) \(air.level)"),
            BackLine(label: "PM2.5", value: air.pm25.map { String(format: "%.0f µg/m³", $0) } ?? Formatting.missing),
            BackLine(label: "更新", value: clock(air.fetchedAt)),
        ]
    }

    var fxBack: [BackLine] {
        guard let fx = info.fx else { return [BackLine(label: "匯率", value: "未有資料")] }
        func line(_ label: String, _ code: String) -> BackLine {
            BackLine(label: label, value: fx.perHKD[code].map { String(format: "%.3f", $0) } ?? Formatting.missing)
        }
        return [line("人民幣", "CNY"), line("台幣", "TWD"), line("英鎊", "GBP")]
    }

    var goldBack: [BackLine] {
        guard let price = info.gold?.usdPerOunce else { return [BackLine(label: "黃金", value: "未有資料")] }
        // 1 金衡盎司 = 31.1035 克；1 両 = 37.429 克
        return [
            BackLine(label: "每克", value: "US$\(Formatting.gold(price / 31.1035))"),
            BackLine(label: "每両", value: "US$\(Formatting.gold(price / 31.1035 * 37.429))"),
            BackLine(label: "更新", value: clock(info.gold?.fetchedAt)),
        ]
    }

    var osBack: [BackLine] {
        let latest: String
        switch osStatus {
        case .updateAvailable(let version): latest = "\(version)（可更新）"
        case .upToDate: latest = "已是最新"
        case .unknown: latest = "未有資料"
        }
        return [
            BackLine(label: "現時", value: stats.versionText),
            BackLine(label: "最新", value: info.latestOS ?? Formatting.missing),
            BackLine(label: "狀態", value: latest),
        ]
    }

    var vpsBack: [BackLine] {
        guard let status = vps.status else { return [BackLine(label: "VPS", value: "未有資料")] }
        return [
            BackLine(label: "系統", value: "\(status.os) · \(status.kernel)"),
            BackLine(label: "更新", value: "\(status.upgradable) 項（安全 \(status.security)）· \(status.rebootRequired ? "要重啟" : "毋須重啟")"),
            BackLine(label: "伺服器", value: status.updatedAt.map { "更新 \(Formatting.clock($0))" } ?? "更新時間不明"),
        ]
    }

    /// 今日咭背面：更份詳情同未來幾日。
    var todayBack: [BackLine] {
        var lines: [BackLine] = []
        if let day = dutyToday {
            var detail = [day.code]
            if let sheet = day.datedSheet { detail.append("Sheet \(sheet)") }
            if let hours = day.hoursText { detail.append(hours) }
            lines.append(BackLine(label: "今日", value: detail.joined(separator: " · ")))
            if let meal = day.mealText { lines.append(BackLine(label: "用膳", value: meal.replacingOccurrences(of: "用膳 ", with: ""))) }
        }
        for offset in 1...4 {
            guard lines.count < 5, let date = Days.add(serviceToday, offset), let day = schedule.duty(on: date) else { continue }
            let value = [day.title, day.times].compactMap { $0 }.joined(separator: " ")
            lines.append(BackLine(label: shortDay(date), value: value))
        }
        return lines
    }

    private func shortDay(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        let names = ["一", "二", "三", "四", "五", "六", "日"]
        guard parts.count == 3, let index = Days.weekdayIndex(date) else { return date }
        return "\(names[index]) \(parts[1])/\(parts[2])"
    }
}
