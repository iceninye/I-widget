import ActivityKit
import SwiftUI
import WidgetKit

/// 更份倒數：鎖定畫面同動態島顯示「下一件事」同倒數，加之後兩件事。
/// 倒數數字由系統自己跳；`staleDate` = 事件時間，過咗之後 `isStale` 變 true，顯示「已到時間」。
struct DutyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DutyActivityAttributes.self) { context in
            DutyLockScreenView(state: context.state, stale: context.isStale)
                .padding(14)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: DutyActivityStyle.symbol(context.state.kind))
                        .font(.title2)
                        .foregroundStyle(DutyActivityStyle.tint(context.state.kind))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DutyCountdownText(state: context.state, stale: context.isStale)
                        .font(.title2.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail).font(.footnote).lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: DutyActivityStyle.symbol(context.state.kind))
                    .foregroundStyle(DutyActivityStyle.tint(context.state.kind))
            } compactTrailing: {
                DutyCountdownText(state: context.state, stale: context.isStale)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: DutyActivityStyle.symbol(context.state.kind))
                    .foregroundStyle(DutyActivityStyle.tint(context.state.kind))
            }
        }
    }
}

enum DutyActivityStyle {
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "on": return "sunrise.fill"
        case "pick": return "tram.fill"
        case "drop": return "arrow.down.circle.fill"
        default: return "house.fill"
        }
    }

    static func tint(_ kind: String) -> Color {
        switch kind {
        case "on": return .orange
        case "pick": return .green
        case "drop": return .blue
        default: return .purple
        }
    }
}

/// 倒數到 `state.at`；過咗（stale）就顯示「已到」。
struct DutyCountdownText: View {
    let state: DutyActivityState
    let stale: Bool

    var body: some View {
        if stale {
            Text("已到時間").monospacedDigit().multilineTextAlignment(.trailing)
        } else {
            // 範圍要 lowerBound <= upperBound，否則會 crash：事件時間已過就用事件時間做起點
            Text(timerInterval: min(Date.now, state.at)...state.at, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
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
                Text(state.title).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                DutyCountdownText(state: state, stale: stale)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: 120, alignment: .trailing)
            }
            Text(state.detail).font(.subheadline).lineLimit(2)
            if !state.later.isEmpty {
                Divider()
                ForEach(state.later, id: \.self) { item in
                    Text(item).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
