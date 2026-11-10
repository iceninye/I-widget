import Foundation
import UserNotifications

/// 交接提示嘅本地通知：每次重排都先清走舊嘅 `handover.*`，再排今日同明日仲未響嘅。
/// 免費簽名冇 Time Sensitive，所以係普通通知。提示聲係用語音合成錄好嘅句子（`SpokenSound`），
/// 由手機喇叭直接讀出；錄唔到就用預設提示聲。
enum HandoverNotifier {
    static let enabledKey = "settings.handoverAlerts"
    /// iOS 最多排 64 個本地通知，留位俾其他用途。
    static let limit = 60

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(HandoverAlerts.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// 關咗交接提示：通知同語音檔全部刪走。
    static func disable() async {
        await removeAll()
        SpokenSound.removeAll()
    }

    static let lastSpokenKey = "handover.lastSpoken"

    private static func makeContent(_ alert: HandoverAlert, settings: HandoverSettings) async -> (UNMutableNotificationContent, Bool) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.threadIdentifier = "handover"
        if settings.speak, let sound = await SpokenSound.make(id: alert.id, text: alert.body, settings: settings) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
            return (content, true)
        }
        content.sound = .default
        return (content, false)
    }

    /// 回傳排咗幾多個。有幾多個錄到語音記喺 `lastSpokenKey`（設定頁顯示用）。
    @discardableResult
    static func schedule(_ alerts: [HandoverAlert], settings: HandoverSettings = .load(), now: Date = Date()) async -> Int {
        await removeAll()
        let center = UNUserNotificationCenter.current()
        let upcoming = Array(alerts.filter { $0.fireAt > now }.prefix(limit))
        // 舊語音檔（已經響完或者內容改咗）先刪，只留今次用得着嘅
        let keep = settings.speak ? Set(upcoming.map { SpokenSound.fileName(id: $0.id, text: $0.body, settings: settings) }) : []
        SpokenSound.removeAll(except: keep)
        var count = 0
        var spoken = 0
        for alert in upcoming {
            let (content, hasVoice) = await makeContent(alert, settings: settings)
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert.fireAt)
            let request = UNNotificationRequest(
                identifier: alert.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            if (try? await center.add(request)) != nil {
                count += 1
                if hasVoice { spoken += 1 }
            }
        }
        UserDefaults.standard.set(spoken, forKey: lastSpokenKey)
        return count
    }

    /// 測試通知：5 秒後響一次，用嚟試聲。回傳有冇錄到語音。
    static func test(_ text: String, settings: HandoverSettings) async -> Bool {
        let alert = HandoverAlert(
            id: "\(HandoverAlerts.idPrefix)test", kind: .pickUp, fireAt: Date(), eventAt: Date(), title: "交接提示測試", body: text
        )
        let (content, hasVoice) = await makeContent(alert, settings: settings)
        let request = UNNotificationRequest(
            identifier: alert.id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
        return hasVoice
    }

    /// 下一個會響嘅提示（設定頁顯示用）。
    static func next() async -> (Date, String)? {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending
            .filter { $0.identifier.hasPrefix(HandoverAlerts.idPrefix) }
            .compactMap { request -> (Date, String)? in
                guard let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() else { return nil }
                return (date, request.content.body)
            }
            .min { $0.0 < $1.0 }
    }

    static func pendingCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(HandoverAlerts.idPrefix) }.count
    }
}

/// App 喺前景時通知照樣彈出同出聲（預設前景係唔顯示）。
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
