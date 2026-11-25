import SwiftUI
import UserNotifications

@main
struct iWidgetApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        WidgetBackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
