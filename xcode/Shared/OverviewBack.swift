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
        var lines = [
            BackLine(label: "電量", value: Formatting.percent(stats.batteryLevel)),
            BackLine(label: "狀態", value: (stats.isFullyCharged ? "已充滿" : stats.isCharging ? "充電中" : "使用電池") + (stats.isLowPowerMode ? " · 低耗電" : ""))
        ]
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

    var memoryBack: [BackLine] {
        guard let total = stats.memoryTotal else { return [BackLine(label: "記憶體", value: "讀唔到")] }
        var lines = [BackLine(label: "總共", value: Formatting.bytes(total))]
        if let available = stats.memoryAvailable {
            lines.insert(BackLine(label: "可用", value: Formatting.bytes(available)), at: 0)
            lines.insert(BackLine(label: "已用", value: Formatting.percent(Formatting.usedFraction(free: available, total: total))), at: 1)
        }
        return lines
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

    var airBack: [BackLine] {
        guard let air = info.air else { return [BackLine(label: "香港 AQHI", value: "未有資料")] }
        return [
            BackLine(label: "香港 AQHI", value: "\(air.index) · \(air.level)"),
            BackLine(label: "測站", value: air.station),
        ]
    }

    var regionalBack: [BackLine] {
        guard let regional = info.regional else { return [BackLine(label: "地區觀測", value: "未有資料")] }
        return [
            BackLine(label: "風力測站", value: regional.windStation ?? Formatting.missing),
            BackLine(label: "風向", value: regional.windDirection ?? Formatting.missing),
            BackLine(label: "平均風速", value: regional.windSpeed.map { String(format: "%.0f km/h", $0) } ?? Formatting.missing),
            BackLine(label: "最高陣風", value: regional.gust.map { String(format: "%.0f km/h", $0) } ?? Formatting.missing),
            BackLine(label: "風力時間", value: Formatting.sourceTime(regional.windObservedAt)),
            BackLine(label: "氣壓測站", value: regional.pressureStation ?? Formatting.missing),
            BackLine(label: "海平面氣壓", value: regional.pressure.map { String(format: "%.1f hPa", $0) } ?? Formatting.missing),
            BackLine(label: "氣壓時間", value: Formatting.sourceTime(regional.pressureObservedAt)),
        ]
    }

    var sunBack: [BackLine] {
        guard let sun = info.sun, sun.date == Days.calendarDate(date) else {
            return [BackLine(label: "日出日落", value: "未有今日資料")]
        }
        return [BackLine(label: "日出", value: sun.sunrise), BackLine(label: "日落", value: sun.sunset)]
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
            BackLine(label: "每金衡盎司", value: "US$\(Formatting.gold(price))"),
            BackLine(label: "每克", value: "US$\(Formatting.gold(price / 31.1035))"),
            BackLine(label: "每両", value: "US$\(Formatting.gold(price / 31.1035 * 37.429))"),
            BackLine(label: "讀取時間", value: Formatting.sourceTime(info.gold?.fetchedAt)),
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
            BackLine(label: "Xray", value: status.xrayRunning.map { $0 ? "運行中" : "未運行" } ?? "未有資料"),
            BackLine(label: "Hysteria 2", value: status.hysteria2Listening.map { $0 ? "監聽中" : "未監聽" } ?? "未有資料"),
            BackLine(label: "伺服器資料時間", value: Formatting.sourceTime(status.updatedAt)),
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
