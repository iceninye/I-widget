import ActivityKit
import SwiftUI
import WidgetKit

/// 更份倒數：鎖定畫面同動態島顯示「下一件事」——主行只係動作、右側只係倒數、
/// 次行「時間 · 地點」、再一行補充資料，之後嘅事另外列（最多兩個）。
/// 倒數數字由系統自己跳；主事件過咗時間就靠 `ActivityContent.staleDate`（= `state.at`）兜底：
/// `isStale` 變 true → 改講「待更新」+「上次事件：HH:mm 動作」，唔好當件事已完成、亦唔好當過期事件即將發生。
/// 「之後」兩行只係喺**渲染嗰一刻**用 `Date.now` 過濾，Live Activity 唔會自己重畫，
/// 所以唔好當佢哋會自動收起／自動過期——真過咗頭就靠上面個 `staleDate` 轉「待更新」。
struct DutyLiveActivity: Widget {
    /// 撳入 Live Activity 就返去 app 嘅更份頁（app 側由 `iwidget://` handler 處理）。
    /// 用 `widgetURL` 唔用 Button：extension 讀唔到 app 嘅 token，相關 AppIntent 亦只喺 app target。
    static let dutyURL = URL(string: "iwidget://duty")

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DutyActivityAttributes.self) { context in
            DutyLockScreenView(state: context.state, stale: context.isStale)
                .padding(14)
                .widgetURL(Self.dutyURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading, priority: 1) {
                    Image(systemName: DutyActivityStyle.symbol(context.state.kind))
                        .font(.title2)
                        .foregroundStyle(DutyActivityStyle.tint(context.state.kind))
                        .accessibilityLabel(context.state.action)
                }
                DynamicIslandExpandedRegion(.center, priority: 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.isStale ? "待更新" : context.state.action)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        DutyPlaceLine(state: context.state, stale: context.isStale)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .widgetURL(Self.dutyURL)
                    .accessibilityLabel(context.state.accessibilityText(now: Date.now, stale: context.isStale))
                }
                // 倒數放 bottom，唔同 center 搶寬
                DynamicIslandExpandedRegion(.bottom, priority: 1) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if !context.isStale {
                                DutyCountdownText(state: context.state, stale: context.isStale)
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: 110, alignment: .trailing)
                            }
                            if !context.state.note.isEmpty {
                                Text(context.state.note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                        DutyFollowUpLines(state: context.state, stale: context.isStale)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .widgetURL(Self.dutyURL)
                }
            } compactLeading: {
                Image(systemName: DutyActivityStyle.symbol(context.state.kind))
                    .foregroundStyle(DutyActivityStyle.tint(context.state.kind))
                    .accessibilityLabel(context.state.action)
            } compactTrailing: {
                // 呢度好窄：行事件時刻（05:20），唔塞 h:mm:ss 倒數
                if context.isStale {
                    Text("待更新")
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel("待更新")
                } else {
                    Text(context.state.at, style: .time)
                        .font(.caption2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityLabel("\(context.state.action) \(Formatting.clock(context.state.at))")
                }
            } minimal: {
                Image(systemName: DutyActivityStyle.symbol(context.state.kind))
                    .foregroundStyle(DutyActivityStyle.tint(context.state.kind))
                    .accessibilityLabel(context.state.accessibilityText(now: Date.now, stale: context.isStale))
            }
            .widgetURL(Self.dutyURL)
        }
    }
}

enum DutyActivityStyle {
    /// 動作 → 圖標／顏色：一律經 `HandoverAlert.Kind(rawValue:)` 映射，唔喺呢度重複寫 raw string。
    /// 認唔到（舊內容缺 `kind`、空字串）用中性圖標＋灰色，唔會冒充某個動作；
    /// 兩邊都唔寫 `default`：`Kind` 將來加 case 時編譯器會話你知要補。
    static func symbol(_ raw: String) -> String {
        switch HandoverAlert.Kind(rawValue: raw) {
        case .on: return "sunrise.fill"
        case .pickUp: return "tram.fill"
        case .dropOff: return "arrow.down.circle.fill"
        case .off: return "house.fill"
        case nil: return "clock.fill"
        }
    }

    static func tint(_ raw: String) -> Color {
        switch HandoverAlert.Kind(rawValue: raw) {
        case .on: return .orange
        case .pickUp: return .green
        case .dropOff: return .blue
        case .off: return .purple
        case nil: return .gray
        }
    }
}

/// 倒數到 `state.at`：一行、等寬數字、細到企得入容器（唔用 fixedSize，唔會溢出）。
/// stale 就唔好再扮有倒數，改講「待更新」。
struct DutyCountdownText: View {
    let state: DutyActivityState
    let stale: Bool

    var body: some View {
        if stale {
            Text("待更新")
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("待更新")
        } else {
            // 範圍要 lowerBound <= upperBound，否則會 crash：事件時間已過就用事件時間做起點
            Text(timerInterval: min(Date.now, state.at)...state.at, countsDown: true)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("倒數 \(Formatting.clock(state.at)) 後")
        }
    }
}

/// 次行：「時間 · 地點」（stale 時標明呢個係上次事件嘅時間）
struct DutyPlaceLine: View {
    let state: DutyActivityState
    let stale: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(state.at, style: .time)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(stale ? Color.secondary : Color.primary)
            if !state.place.isEmpty {
                Text("·").font(.subheadline).foregroundStyle(.secondary)
                Text(state.place)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stale ? "上次事件" : "事件時間") \(Formatting.clock(state.at)) \(state.place)")
    }
}

/// stale：只講「上次事件」；未 stale：列渲染嗰一刻仲未過期嘅之後事項。
/// 呢個過濾只係展示層（`upcoming` 每次重畫先計一次），唔係逐行自動收起；
/// 主事件真係過咗頭，系統會因 `staleDate` 將成個活動變 `isStale`，轉做「待更新」。
struct DutyFollowUpLines: View {
    let state: DutyActivityState
    let stale: Bool

    private var upcoming: [DutyLaterItem] { state.upcomingLater(now: Date.now) }

    var body: some View {
        if stale {
            Text("上次事件：\(Formatting.clock(state.at)) \(state.action)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("資料待更新，上次事件 \(Formatting.clock(state.at)) \(state.action)")
        } else if !upcoming.isEmpty {
            Divider()
            ForEach(upcoming) { item in
                DutyLaterRow(item: item)
            }
        }
    }
}

/// 「之後」一行：動作 · 地點 · 時刻
struct DutyLaterRow: View {
    let item: DutyLaterItem

    var body: some View {
        HStack(spacing: 6) {
            Text(item.action)
                .font(.footnote)
                .foregroundStyle(DutyActivityStyle.tint(item.kind))
                .lineLimit(1)
            if !item.place.isEmpty {
                Text(item.place).font(.footnote).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Text(item.at, style: .time).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.action) \(Formatting.clock(item.at)) \(item.place)")
    }
}

struct DutyLockScreenView: View {
    let state: DutyActivityState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: DutyActivityStyle.symbol(state.kind))
                    .foregroundStyle(DutyActivityStyle.tint(state.kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text(stale ? "待更新" : state.action)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    DutyPlaceLine(state: state, stale: stale)
                }
                Spacer(minLength: 0)
                if !stale {
                    DutyCountdownText(state: state, stale: stale)
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }
            if !state.note.isEmpty {
                Text(state.note)
                    .font(.subheadline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            DutyFollowUpLines(state: state, stale: stale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityText(now: Date.now, stale: stale))
    }
}
