import BackgroundTasks
import Foundation
import UIKit

enum WidgetBackgroundRefresh {
    static let identifier = "com.iceninye.i-widget.scriptable-refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task { await handle(task) }
        }
    }

    static func scheduleNext(hasCourtData: Bool = true) {
        guard (try? ScriptableFolderStore().loadBookmark()) != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        let now = Date()
        request.earliestBeginDate = CourtPublication.nextReload(
            now: now, holidays: PublicHolidays.cached(), hasCourtData: hasCourtData
        )
        try? BGTaskScheduler.shared.submit(request)
    }

    @MainActor
    static func flush(_ bridge: ScriptableBridgeController) {
        guard bridge.hasAuthorization else { return }
        let state = EndState()
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "Scriptable JSON flush") {
            state.end()
        }
        guard taskID != .invalid, state.start(taskID) else {
            if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            return
        }
        Task { @MainActor in
            await bridge.flush()
            scheduleNext(hasCourtData: bridge.hasCourtData)
            state.end()
        }
    }

    private static func handle(_ task: BGTask) async {
        guard (try? ScriptableFolderStore().loadBookmark()) != nil else {
            task.setTaskCompleted(success: false)
            return
        }
        let work = Task {
            let snapshot = await WidgetSnapshotService.export()
            let status = await ScriptableBridgeWriter.shared.write(snapshot)
            return (success: status.state == .writtenAwaitingCloud,
                    hasCourtData: snapshot.courts.items.contains { !$0.error && $0.total > 0 })
        }
        let completion = BackgroundCompletion(task)
        // 到期同工作完成可能同時發生；只准第一次通知系統。
        task.expirationHandler = {
            work.cancel()
            completion.complete(success: false)
        }
        let result = await work.value
        completion.complete(success: result.success)
        RefreshQueue.recordRefreshAttempt(at: Date())
        scheduleNext(hasCourtData: result.hasCourtData)
    }

    private final class BackgroundCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private let task: BGTask
        private var completed = false

        init(_ task: BGTask) { self.task = task }

        func complete(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return }
            completed = true
            task.setTaskCompleted(success: success)
        }
    }

    private final class EndState: @unchecked Sendable {
        private let lock = NSLock()
        private var taskID: UIBackgroundTaskIdentifier = .invalid
        private var ended = false

        func start(_ taskID: UIBackgroundTaskIdentifier) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !ended else { return false }
            self.taskID = taskID
            return true
        }

        func end() {
            lock.lock()
            defer { lock.unlock() }
            guard !ended, taskID != .invalid else { return }
            ended = true
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }
}
