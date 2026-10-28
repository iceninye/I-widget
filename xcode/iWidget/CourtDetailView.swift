import SwiftUI

@MainActor
struct CourtDetailView: View {
    @State private var selectedCode: String
    @State private var selectedDate: Date
    @State private var search = ""
    @State private var days: [String: CourtDay] = [:]
    @State private var pending = Set<String>()
    @State private var generation = UUID()
    @State private var reload = 0

    init(initialCode: String? = nil, initialDate: String? = nil) {
        let code = initialCode.flatMap { candidate in CourtCatalog.all.first { $0.code == candidate }?.code } ?? ""
        _selectedCode = State(initialValue: code)
        _selectedDate = State(initialValue: initialDate.flatMap { CourtList.date(fromISO: $0) } ?? CourtList.listDate(now: Date()))
    }

    private struct Request: Equatable {
        let code: String
        let date: String
        let reload: Int

        var codes: [String] { code.isEmpty ? CourtCatalog.allCodes : [code] }
    }

    private var request: Request {
        Request(code: selectedCode, date: CourtList.isoDate(selectedDate), reload: reload)
    }

    var body: some View {
        let current = request
        List {
            Section {
                DatePicker("排期日期", selection: $selectedDate, displayedComponents: .date)
                Picker("法院", selection: $selectedCode) {
                    Text("全部法院（不重複裁判法院）").tag("")
                    ForEach(CourtCatalog.all, id: \.code) { court in Text(court.name).tag(court.code) }
                }
            } footer: {
                Text(CourtList.sourceNotice)
            }
            if !pending.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("正在讀取 \(pending.count) 個法院；已完成的結果可先查閱")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(current.codes, id: \.self) { code in
                CourtDetailSection(code: code, dateCode: CourtList.dateCode(selectedDate),
                                   day: days[code], loading: pending.contains(code), search: search)
            }
        }
        .environment(\.timeZone, ICalendar.hongKong.timeZone)
        .navigationTitle("法院案件表")
        .searchable(text: $search, prompt: "搜尋案件編號（不搜尋訴訟各方）")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { reload += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("重新讀取案件表")
            }
        }
        .refreshable { reload += 1 }
        .task(id: current) { await load(current) }
    }

    private func load(_ request: Request) async {
        guard let day = CourtList.date(fromISO: request.date), !Task.isCancelled else { return }
        let id = UUID()
        generation = id
        days = [:]
        pending = Set(request.codes)
        _ = await CourtList.loadAll(codes: request.codes, day: day, now: Date(), forceReload: request.reload > 0) { result in
            await MainActor.run {
                guard !Task.isCancelled, generation == id, self.request == request else { return }
                days[result.code] = result
                pending.remove(result.code)
            }
        }
        guard !Task.isCancelled, generation == id, self.request == request else { return }
        pending = []
    }
}

private struct CourtDetailSection: View {
    let code: String
    let dateCode: String
    let day: CourtDay?
    let loading: Bool
    let search: String

    private var matching: [CourtCase] {
        guard let day, day.dateCode == dateCode else { return [] }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? day.cases : day.cases.filter { $0.caseNo.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Section {
            if let day, day.dateCode == dateCode {
                status(day)
                let cases = matching
                if cases.isEmpty, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, day.total > 0 {
                    Text("已解析記錄中沒有符合的案號（\(day.total) 宗）")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(cases.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.caseNo).font(.headline).textSelection(.enabled)
                        HStack(alignment: .top) {
                            Text(item.minutes == nil ? "時間未列" : "排期 \(item.timeText)").monospacedDigit()
                            if !item.room.isEmpty { Text(item.room) }
                        }
                        .font(.subheadline)
                        if !item.judge.isEmpty { Text(item.judge).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            } else {
                HStack {
                    if loading { ProgressView() }
                    Text(loading ? "讀取此法院中…" : "尚未取得此日期的案件表")
                        .foregroundStyle(.secondary)
                }
            }
            if let url = CourtList.url(code: code, dateCode: dateCode) {
                Link("司法機構原頁及附件", destination: url)
            }
        } header: {
            Text(CourtCatalog.name(code))
        }
    }

    @ViewBuilder private func status(_ day: CourtDay) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.metadata.label(total: day.total, error: day.error, at: Date()))
                .font(.subheadline.bold())
                .foregroundStyle(day.error || day.metadata.isStale(at: Date()) ? Color.orange : Color.secondary)
            if let failure = day.metadata.failure { Text(failure).foregroundStyle(.orange) }
            if day.metadata.source == .officialNoList {
                Text("讀取時原頁表示未提供案件表；不代表當日沒有聆訊。")
            } else if day.metadata.source == .parsed {
                Text("已解析 \(day.total) 宗；排期時間不是即時開庭或完庭狀態。")
            }
            Text(day.metadata.fetchedAt.map { "成功讀取：\(timestamp($0))" } ?? "成功讀取：未有")
            Text(day.metadata.publishedAt.map { "來源公布：\(timestamp($0))" } ?? "來源公布時間：未提供，讀取時間並非公布時間")
            if day.error, let attempted = day.metadata.attemptedAt {
                Text("最近嘗試：\(timestamp(attempted))")
            }
        }
        .font(.footnote).foregroundStyle(.secondary)
    }

    private func timestamp(_ date: Date) -> String {
        let calendar = ICalendar.hongKong
        return CourtList.isoDate(date) + String(format: " %02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
}
