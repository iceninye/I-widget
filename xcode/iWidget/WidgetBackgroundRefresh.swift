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

    static func scheduleNext() {
        guard (try? ScriptableFolderStore().loadBookmark()) != nil else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(RefreshQueue.routineRefreshInterval)
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
            scheduleNext()
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
            return status.state == .writtenAwaitingCloud
        }
        task.expirationHandler = {
            work.cancel()
        }
        let success = await work.value
        RefreshQueue.recordRefreshAttempt(at: Date())
        scheduleNext()
        task.setTaskCompleted(success: success)
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
