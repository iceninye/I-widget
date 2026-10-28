import SwiftUI

struct DataView: View {
    @ObservedObject var model: AppModel
    var page: AppRoute = .info
    @State private var schoolDate = Date()

    private var title: String {
        switch page {
        case .today: return "今日更份"
        case .weather: return "天氣與環境"
        case .school: return "學校日程"
        case .finance: return "財經資訊"
        case .device: return "裝置與服務"
        default: return "各項資訊"
        }
    }

    var body: some View {
        let entry = model.entry
        List {
            switch page {
            case .today: today(entry)
            case .weather: weather(entry)
            case .school: school(entry)
            case .finance: finance(entry)
            case .device: device(entry)
            default: overview(entry)
            }
            Section {
                Text("上次讀取 \(Formatting.sourceTime(entry.updatedAt))")
                Text("資料時間以各來源標示為準；向下拉動可重新讀取。")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .navigationTitle(title)
        .refreshable { await model.refresh() }
        .toolbar {
            if model.loading { ProgressView().accessibilityLabel("正在更新資料") }
        }
    }

    @ViewBuilder private func overview(_ entry: OverviewEntry) -> some View {
        alerts(entry)
        Section("天氣與環境") {
            NavigationLink(value: AppRoute.weather) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.info.weather?.station ?? "香港天文台")
                        Text(entry.info.weather?.currentCode.map(WeatherCode.text) ?? "實況未有資料")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formatting.degrees(entry.info.weather?.currentTemp))
                        .font(.largeTitle.weight(.semibold)).monospacedDigit()
                }
            }
            if let weather = entry.info.weather {
                sourceTime(weather.observedAt, now: entry.date)
            }
            if let air = entry.info.air {
                LabeledContent("香港 AQHI · \(air.station)", value: "\(air.index) · \(air.level)")
                airTime(air, now: entry.date)
            } else {
                LabeledContent("香港 AQHI", value: "未有資料")
            }
        }
        Section("學校") {
            NavigationLink(value: AppRoute.school) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.schoolToday.cycle.first.map { "今日 · \($0)" } ?? "學校日程")
                    if let event = entry.schoolToday.items.first ?? entry.schoolTomorrow.items.first {
                        Text(event.title).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text(entry.schedule.schoolFailed.isEmpty ? "今明兩日未有活動" : "部分日曆未能讀取")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if let holiday = entry.nextHoliday {
                LabeledContent(holiday.title, value: "\(holiday.daysAway) 日後")
            }
        }
        Section("更多資訊") {
            NavigationLink(value: AppRoute.finance) { Label("黃金與匯率", systemImage: "chart.line.uptrend.xyaxis") }
            NavigationLink(value: AppRoute.device) { Label("電量、儲存與 VPS", systemImage: "iphone.gen3") }
        }
    }

    @ViewBuilder private func alerts(_ entry: OverviewEntry) -> some View {
        Section("天氣警告與交通") {
            if let warnings = entry.info.currentWarnings(at: entry.date) {
                if warnings.isEmpty {
                    Label("上次查詢未有生效警告", systemImage: "checkmark.shield")
                } else {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning.text, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(warning.severe ? .red : .orange)
                    }
                }
            } else {
                Label("未能確認最新天氣警告", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            }
            if let train = entry.info.currentTrain(at: entry.date) {
                LabeledContent("屯門站 · 屯馬綫", value: train.state.text)
                if !train.message.isEmpty { Text(train.message).font(.footnote).foregroundStyle(.secondary) }
                Text("車站 API 狀態，唔代表全綫所有路段；\(Formatting.sourceTime(train.fetchedAt))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("列車資料暫時未能更新").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func today(_ entry: OverviewEntry) -> some View {
        Section {
            if !entry.schedule.configured {
                ContentUnavailableView("未設定更表", systemImage: "calendar.badge.exclamationmark",
                                       description: Text("請到「設定」填入 tml-roster token。App 同 Widget 需要各自設定。"))
            } else if let day = entry.dutyToday {
                Text(day.title).font(.title2.weight(.semibold))
                if let times = day.times { Text(times).font(.largeTitle.weight(.semibold)).monospacedDigit() }
                if let route = day.route { LabeledContent("地點", value: route) }
                if let meal = day.mealText { LabeledContent("用膳", value: meal) }
                if let hours = day.hoursText { LabeledContent("工時", value: hours) }
                LabeledContent("更份編號", value: day.code)
                if let sheet = day.datedSheet { LabeledContent("更表版本", value: sheet) }
                if let hint = day.hint { Text(hint).foregroundStyle(.orange) }
            } else {
                Text(entry.schedule.rosterFailed ? "更表讀取失敗，請檢查 token 同網絡。" : "更表未有今日資料。")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(entry.serviceToday)
        } footer: {
            if entry.schedule.rosterFailed, entry.schedule.roster != nil {
                Text("暫時顯示已儲存更表；最新資料未能讀取。")
            }
        }
        if entry.schedule.configured {
            if let week = entry.weekSummary {
                Section("本週概況") { Text(week.text) }
            }
            Section("未來七日") {
                ForEach(0..<7, id: \.self) { offset in
                    if let date = Days.add(entry.serviceToday, offset) {
                        let day = entry.schedule.duty(on: date)
                        VStack(alignment: .leading, spacing: 5) {
                            LabeledContent(date, value: day?.title ?? "未有資料")
                            if let times = day?.times { Text(times).monospacedDigit().font(.headline) }
                            if let route = day?.route { Text(route).font(.subheadline).foregroundStyle(.secondary) }
                            if day?.isOverride == true { Text("已改更").font(.caption).foregroundStyle(.orange) }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    @ViewBuilder private func weather(_ entry: OverviewEntry) -> some View {
        alerts(entry)
        Section("現時天氣") {
            if let weather = entry.info.weather {
                LabeledContent(weather.station, value: Formatting.degrees(weather.currentTemp))
                if let code = weather.currentCode { Text(WeatherCode.text(code)) }
                LabeledContent("相對濕度", value: weather.humidity.map { String(format: "%.0f%%", $0) } ?? Formatting.missing)
                LabeledContent("紫外線 · 京士柏", value: weather.uvIndex.map { String(format: "%.1f · %@", $0, UVLevel.text($0)) } ?? "未提供")
                sourceTime(weather.observedAt, now: entry.date)
            } else { Text("未能讀取天文台實況").foregroundStyle(.secondary) }
        }
        Section("香港空氣質素健康指數") {
            lines(entry.airBack)
            if let air = entry.info.air { airTime(air, now: entry.date) }
        }
        Section("地區風力與氣壓") { lines(entry.regionalBack) }
        Section("今日天文資料") { lines(entry.sunBack) }
        Section("九天天氣預報") {
            if let weather = entry.info.weather, !weather.forecast.isEmpty {
                ForEach(weather.forecast, id: \.date) { day in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(day.date).font(.headline)
                            Spacer()
                            Image(systemName: WeatherCode.symbol(day.code))
                            Text(Formatting.tempRange(day)).monospacedDigit()
                        }
                        Text(day.summary.isEmpty ? WeatherCode.text(day.code) : day.summary)
                        if !day.wind.isEmpty { Text(day.wind).font(.subheadline).foregroundStyle(.secondary) }
                        if let rain = day.rainChance { Text("降雨機會：\(rain)").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 5)
                }
                Text("預報發布：\(Formatting.sourceTime(weather.forecastUpdatedAt))").font(.caption).foregroundStyle(.secondary)
            } else { Text("未能讀取九天天氣預報").foregroundStyle(.secondary) }
        }
        Section("資料來源") {
            Link("香港天文台開放數據", destination: URL(string: "https://www.hko.gov.hk/en/abouthko/opendata_intro.htm")!)
            Link("環保署 AQHI", destination: URL(string: "https://data.gov.hk/en-data/dataset/hk-epd-airteam-current-aqhi-of-individual-air-quality-monitoring-stations")!)
        }
    }

    @ViewBuilder private func school(_ entry: OverviewEntry) -> some View {
        Section {
            DatePicker("日期", selection: $schoolDate,
                       in: ICalendar.hongKong.startOfDay(for: entry.date)...entry.date.addingTimeInterval(60 * 86_400),
                       displayedComponents: .date)
                .environment(\.timeZone, ICalendar.hongKong.timeZone)
            Text("活動顯示未來 60 日已載入資料；日程以學校公布為準。")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("當日日程") {
            let day = entry.schedule.school(dayStart: ICalendar.hongKong.startOfDay(for: schoolDate))
            ForEach(day.cycle, id: \.self) { LabeledContent("循環日", value: $0) }
            ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.headline)
                    Text(item.allDay ? "全日" : Formatting.clock(item.start, calendar: ICalendar.hongKong))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            if day.items.isEmpty { Text("已載入嘅日曆未有當日活動。") .foregroundStyle(.secondary) }
            if !entry.schedule.schoolFailed.isEmpty {
                Text("未能讀取：\(entry.schedule.schoolFailed.joined(separator: "、"))").foregroundStyle(.orange)
            }
        }
        if let holiday = entry.nextHoliday {
            Section("下一個假期") {
                LabeledContent(holiday.title, value: holiday.rangeText)
                Text("\(holiday.daysAway) 日後").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func finance(_ entry: OverviewEntry) -> some View {
        Section("黃金") { lines(entry.goldBack) }
        Section("匯率 · 每 1 港元") {
            if let fx = entry.info.fx {
                ForEach(fx.perHKD.keys.sorted(), id: \.self) { code in
                    LabeledContent(code, value: String(format: "%.4f", fx.perHKD[code] ?? 0))
                }
                Text("讀取於 \(Formatting.sourceTime(fx.fetchedAt))").font(.caption).foregroundStyle(.secondary)
            } else { Text("未有匯率資料").foregroundStyle(.secondary) }
        }
        Section {
            Text("現有黃金及匯率來源尚未改為金管局統計，亦非即時交易報價。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func device(_ entry: OverviewEntry) -> some View {
        Section("電量") { lines(entry.batteryBack) }
        Section("儲存空間") { lines(entry.storageBack) }
        Section("開機時間") { lines(entry.uptimeBack) }
        Section("系統") { lines(entry.osBack) }
        Section("VPS") {
            if entry.vps.configured { lines(entry.vpsBack) }
            else { Text("請到「設定」填入 VPS token。").foregroundStyle(.secondary) }
            if entry.vps.failed { Text("最新狀態未能讀取。").foregroundStyle(.orange) }
        }
    }

    private func sourceTime(_ date: Date?, now: Date) -> some View {
        Text("資料時間 \(Formatting.sourceTime(date))\(Formatting.isStale(date, now: now) ? " · 未有最新資料" : "")")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func airTime(_ air: AirQuality, now: Date) -> some View {
        Text("AQHI 發布 \(Formatting.sourceTime(air.observedAt))\(air.isStale(at: now) ? " · 未有最新資料" : "")")
            .font(.caption)
            .foregroundStyle(air.isStale(at: now) ? Color.orange : .secondary)
    }

    private func lines(_ values: [BackLine]) -> some View {
        ForEach(values) { line in LabeledContent(line.label, value: line.value) }
    }
}
