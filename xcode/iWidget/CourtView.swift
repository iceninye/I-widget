import SwiftUI
import UIKit

/// App 內嘅法院案件表：同 widget 一樣唔載入訴訟各方，但列出全部聆訊，撳入去睇詳情。
@MainActor
final class CourtModel: ObservableObject {
    @Published private(set) var days: [CourtDay] = []
    @Published private(set) var listDate = Date()
    @Published private(set) var loading = false
    /// 由 widget 連結帶嚟、等案件表載入後跳去嘅目標。
    @Published var pending: CourtLink?
    @Published var selected: CourtSelection?
    @Published var scrollTo: String?

    func refresh(codes: [String]) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let now = Date()
        let holidays = await withDeadline(12, fallback: PublicHolidays.cached()) { await PublicHolidays.load(now: now) }
        let day = CourtList.listDate(now: now, holidays: holidays)
        listDate = day
        days = await CourtList.loadAll(codes: codes, day: day, now: now)
        resolvePending()
    }

    func open(_ link: CourtLink) {
        pending = link
        resolvePending()
    }

    private func resolvePending() {
        guard let link = pending, let day = days.first(where: { $0.code == link.code }) else { return }
        pending = nil
        if let match = link.match(in: day) {
            selected = CourtSelection(code: day.code, dateCode: day.dateCode, item: match)
        } else {
            scrollTo = day.code
        }
    }
}

struct CourtSelection: Identifiable, Equatable {
    let code: String
    let dateCode: String
    let item: CourtCase
    var id: String { "\(code)|\(item.caseNo)|\(item.minutes ?? -1)|\(item.room)" }
}

struct CourtView: View {
    @ObservedObject var model: CourtModel
    @AppStorage("court.codes") private var storedCodes = "DC,ALLMAG,CFA"
    @State private var query = ""

    private var codes: [String] { storedCodes.split(separator: ",").map(String.init) }

    var body: some View {
        let minute = CourtList.minuteOfDay(now: Date(), listDate: model.listDate)
        ScrollViewReader { proxy in
            List {
                if model.days.isEmpty && !model.loading {
                    Text("撳右上角揀法院。").foregroundStyle(.secondary)
                }
                ForEach(model.days, id: \.code) { day in
                    section(day, minute: minute)
                }
                Section {
                    Text("資料來自司法機構法庭日誌，只公布到下一個工作日；唔顯示訴訟各方。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .onChange(of: model.scrollTo) { _, code in
                guard let code else { return }
                withAnimation { proxy.scrollTo(code, anchor: .top) }
                model.scrollTo = nil
            }
        }
        .navigationTitle("法院 \(CourtList.dayText(model.listDate, now: Date()))")
        .searchable(text: $query, prompt: "案號、法庭、法官")
        .refreshable { await model.refresh(codes: codes) }
        .overlay { if model.loading && model.days.isEmpty { ProgressView() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { picker }
        }
        .task { await model.refresh(codes: codes) }
        .onChange(of: storedCodes) { _, _ in Task { await model.refresh(codes: codes) } }
        .sheet(item: $model.selected) { selection in
            NavigationStack { CourtDetailView(selection: selection, listDate: model.listDate) }
                .presentationDetents([.medium, .large])
        }
    }

    private var picker: some View {
        Menu {
            ForEach(CourtCatalog.all, id: \.code) { court in
                Button {
                    toggle(court.code)
                } label: {
                    if codes.contains(court.code) {
                        Label(court.name, systemImage: "checkmark")
                    } else {
                        Text(court.name)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    private func toggle(_ code: String) {
        var list = codes
        if let index = list.firstIndex(of: code) {
            list.remove(at: index)
        } else {
            list.append(code)
        }
        storedCodes = list.joined(separator: ",")
    }

    private func matches(_ item: CourtCase) -> Bool {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        return [item.caseNo, item.room, item.judge, item.nature ?? ""].contains { $0.localizedCaseInsensitiveContains(text) }
    }

    @ViewBuilder private func section(_ day: CourtDay, minute: Int?) -> some View {
        let cases = day.sortedCases.filter(matches)
        Section {
            if day.error {
                Label("讀取失敗", systemImage: "wifi.exclamationmark").foregroundStyle(.orange)
            } else if day.total == 0 {
                Text("未有案件表").foregroundStyle(.secondary)
            } else if cases.isEmpty {
                Text("冇符合嘅聆訊").foregroundStyle(.secondary)
            }
            ForEach(Array(cases.enumerated()), id: \.offset) { _, item in
                Button {
                    model.selected = CourtSelection(code: day.code, dateCode: day.dateCode, item: item)
                } label: {
                    CourtRow(item: item, status: item.status(atMinute: minute))
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text(day.name)
                Spacer()
                if day.total > 0 { Text("共 \(day.total) 宗") }
            }
        }
        .id(day.code)
    }
}

private struct CourtRow: View {
    let item: CourtCase
    let status: CourtStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(item.timeText).monospacedDigit().fontWeight(.semibold)
                .foregroundStyle(status == .finished ? .secondary : .primary)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.caseNo).font(.subheadline.weight(.medium))
                    if status == .ongoing { Tag(text: "進行中", color: .green) }
                    if let nature = item.nature { Tag(text: nature) }
                }
                Text([item.room, item.judge].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// 一個聆訊嘅詳情。
struct CourtDetailView: View {
    let selection: CourtSelection
    let listDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let item = selection.item
        let minute = CourtList.minuteOfDay(now: Date(), listDate: listDate)
        List {
            Section {
                LabeledContent("案件編號", value: item.caseNo)
                LabeledContent("時間", value: item.timeText)
                LabeledContent("法庭", value: item.room.isEmpty ? Formatting.missing : item.room)
                LabeledContent("法官／審理人員", value: item.judge.isEmpty ? Formatting.missing : item.judge)
                if let nature = item.nature { LabeledContent("性質", value: nature) }
                LabeledContent("法院", value: CourtCatalog.name(selection.code))
                LabeledContent("日期", value: CourtList.dayText(listDate, now: Date()))
                LabeledContent("狀態", value: item.status(atMinute: minute).text)
            }
            Section {
                Button("複製案件編號", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.caseNo }
                if let url = CourtList.url(code: selection.code, dateCode: selection.dateCode) {
                    Link(destination: url) { Label("喺司法機構網頁開啟原案件表", systemImage: "safari") }
                }
            } footer: {
                Text("為保障個人資料，唔顯示訴訟各方；詳情請睇原案件表。")
            }
        }
        .navigationTitle("聆訊詳情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
        }
    }
}

private struct Tag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: Capsule())
    }
}
