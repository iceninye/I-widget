import SwiftUI

/// 同 widget 一樣嘅資料，逐項列出。
struct DataView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let entry = model.entry
        List {
            alerts(entry)
            today(entry)
            school(entry)
            Section("電量、儲存、開機") {
                lines(entry.batteryBack)
                lines(entry.storageBack)
                lines(entry.uptimeBack)
            }
            Section("天氣") { lines(entry.weatherBack) }
            Section("紫外線、空氣、匯率") {
                lines(entry.uvBack)
                lines(entry.airBack)
                lines(entry.fxBack)
            }
            Section("黃金、系統") {
                lines(entry.goldBack)
                lines(entry.osBack)
            }
            Section("VPS") {
                if entry.vps.configured {
                    lines(entry.vpsBack)
                } else {
                    Text("未設定，請去「設定」填 VPS token。").foregroundStyle(.secondary)
                }
            }
            Section {
                Text("更新於 \(Formatting.clock(entry.updatedAt))").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("資料")
        .refreshable { await model.refresh() }
        .overlay { if model.loading { ProgressView() } }
    }

    @ViewBuilder private func alerts(_ entry: OverviewEntry) -> some View {
        let warnings = entry.info.warnings ?? []
        if !warnings.isEmpty || entry.info.train != nil {
            Section("警告、屯馬綫") {
                ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning.text, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(warning.severe ? .red : .orange)
                }
                if let train = entry.info.train {
                    LabeledContent("屯馬綫", value: train.state.text)
                    if !train.message.isEmpty { Text(train.message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
    }

    @ViewBuilder private func today(_ entry: OverviewEntry) -> some View {
        Section("今日咭") {
            if !entry.schedule.configured {
                Text("未設定 tml-roster token，請去「設定」填。").foregroundStyle(.secondary)
            } else if let day = entry.dutyToday {
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.title).font(.headline)
                    if let times = day.times { Text(times).font(.title2.bold()).monospacedDigit() }
                    if let route = day.route { Text(route).foregroundStyle(.secondary) }
                    if let meal = day.mealText { Text(meal).foregroundStyle(.secondary) }
                    if let hours = day.hoursText { Text(hours).foregroundStyle(.secondary) }
                    if let hint = day.hint { Text(hint).font(.footnote).foregroundStyle(.orange) }
                }
                if let week = entry.weekSummary { LabeledContent("本週", value: week.text) }
                lines(Array(entry.todayBack.dropFirst(entry.dutyToday?.mealText == nil ? 1 : 2)))
            } else {
                Text(entry.schedule.rosterFailed ? "讀唔到更表，請檢查 token 同網絡。" : "更表未有今日資料。")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private func school(_ entry: OverviewEntry) -> some View {
        Section("學校") {
            let today = entry.schoolToday
            let tomorrow = entry.schoolTomorrow
            if let cycle = today.cycle.first { LabeledContent("循環周", value: cycle) }
            ForEach(Array(today.items.enumerated()), id: \.offset) { _, item in
                LabeledContent("今 \(item.allDay ? "全日" : Formatting.clock(item.start))", value: item.title)
            }
            ForEach(Array(tomorrow.items.enumerated()), id: \.offset) { _, item in
                LabeledContent("明 \(item.allDay ? "全日" : Formatting.clock(item.start))", value: item.title)
            }
            if let holiday = entry.nextHoliday {
                LabeledContent("下個假期 \(holiday.rangeText)", value: "\(holiday.title) · \(holiday.daysAway) 日後")
            }
            if !entry.schedule.schoolFailed.isEmpty {
                Text("\(entry.schedule.schoolFailed.joined(separator: "、")) 讀唔到").foregroundStyle(.orange)
            }
        }
    }

    private func lines(_ lines: [BackLine]) -> some View {
        ForEach(lines) { line in
            LabeledContent(line.label, value: line.value)
        }
    }
}
