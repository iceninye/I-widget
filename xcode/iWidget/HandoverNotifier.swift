import Foundation
import UserNotifications

/// 交接提示嘅本地通知：每次重排都先清走舊嘅 `handover.*`，再排今日同明日仲未響嘅。
/// 免費簽名冇 Time Sensitive，所以係普通通知（有聲）；開咗 iPhone「朗讀通知」就會讀出內容。
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

    /// 回傳排咗幾多個。
    @discardableResult
    static func schedule(_ alerts: [HandoverAlert], now: Date = Date()) async -> Int {
        await removeAll()
        let center = UNUserNotificationCenter.current()
        var count = 0
        for alert in alerts.filter({ $0.fireAt > now }).prefix(limit) {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.threadIdentifier = "handover"
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert.fireAt)
            let request = UNNotificationRequest(
                identifier: alert.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            if (try? await center.add(request)) != nil { count += 1 }
        }
        return count
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
