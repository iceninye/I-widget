import AppIntents
import SwiftUI
import WidgetKit

/// VPS widget 嘅設定：長按 widget → 編輯 widget。網址同 token 只存喺 iPhone，唔會寫入 repo。
struct VPSConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "VPS 設定"
    static var description = IntentDescription("VPS 狀態網址（https://…/status.json）同 Bearer token。")

    @Parameter(title: "狀態網址（https）")
    var statusURL: String?

    @Parameter(title: "Token")
    var token: String?
}

struct VPSEntry: TimelineEntry {
    let date: Date
    let status: VPSStatus?
    let configured: Bool
    let failed: Bool

    static let sample = VPSEntry(date: Date(), status: .sample, configured: true, failed: false)
}

struct VPSProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VPSEntry { .sample }

    func snapshot(for configuration: VPSConfigIntent, in context: Context) async -> VPSEntry {
        if context.isPreview { return .sample }
        return VPSEntry(
            date: Date(),
            status: DataCache.load(VPSStatus.self, key: "vps"),
            configured: VPSAPI.url(configuration.statusURL) != nil,
            failed: false
        )
    }

    /// 每小時重讀（VPS 嗰邊腳本亦係每小時更新一次）。
    func timeline(for configuration: VPSConfigIntent, in context: Context) async -> Timeline<VPSEntry> {
        let now = Date()
        guard let url = VPSAPI.url(configuration.statusURL) else {
            return Timeline(entries: [VPSEntry(date: now, status: nil, configured: false, failed: false)], policy: .after(now.addingTimeInterval(3_600)))
        }
        let token = (configuration.token ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cached = DataCache.load(VPSStatus.self, key: "vps")
        let entry = await withDeadline(15, fallback: VPSEntry(date: now, status: cached, configured: true, failed: true)) {
            do {
                var request = URLRequest(url: url, timeoutInterval: 10)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let status = try VPSAPI.parse(data)
                DataCache.save(status, key: "vps")
                return VPSEntry(date: now, status: status, configured: true, failed: false)
            } catch {
                return VPSEntry(date: now, status: cached, configured: true, failed: true)
            }
        }
        return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3_600)))
    }
}

struct VPSView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VPSEntry

    private var tint: Color {
        guard let status = entry.status else { return .secondary }
        switch VPSAPI.health(status) {
        case .ok: return .green
        case .attention: return .orange
        case .problem: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "server.rack").foregroundStyle(tint).widgetAccentable()
                Text("VPS").fontWeight(.bold)
                Spacer(minLength: 0)
                RefreshButton()
            }
            .font(.system(size: 13))
            if !entry.configured {
                Text("未設定：長按 widget → 編輯 widget，輸入狀態網址同 token。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let status = entry.status {
                content(status)
            } else {
                Text("讀唔到狀態，請檢查網址、token 同網絡。")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            if entry.configured {
                Text(footer)
                    .font(.system(size: 10))
                    .foregroundStyle(entry.failed ? .orange : .secondary)
            }
        }
    }

    private func content(_ status: VPSStatus) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(status.os).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            row("arrow.triangle.2.circlepath", VPSAPI.updatesText(status), status.security > 0 ? .red : (status.upgradable > 0 ? .orange : .primary))
            row("power", status.rebootRequired ? "需要重啟" : "毋須重啟", status.rebootRequired ? .red : .primary)
            if let xray = status.xrayRunning { row(xray ? "checkmark.circle.fill" : "xmark.circle.fill", "Xray", xray ? .primary : .red) }
            if let hysteria = status.hysteria2Listening { row(hysteria ? "checkmark.circle.fill" : "xmark.circle.fill", "Hysteria2", hysteria ? .primary : .red) }
        }
    }

    private func row(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 14)
            Text(text).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(size: 11))
    }

    private var footer: String {
        let time = entry.status?.updatedAt.map { "伺服器更新 \(Formatting.clock($0))" } ?? "更新時間不明"
        return entry.failed ? "連線失敗，顯示舊資料 · \(time)" : time
    }
}

struct VPSWidget: Widget {
    let kind = "IWidgetVPS"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: VPSConfigIntent.self, provider: VPSProvider()) { entry in
            VPSView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
        .configurationDisplayName("VPS")
        .description("伺服器版本、可更新數、需否重啟，同 Xray／Hysteria2 狀態。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
