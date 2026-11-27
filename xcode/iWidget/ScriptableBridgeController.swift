import Foundation

@MainActor
final class ScriptableBridgeController: ObservableObject {
    @Published private(set) var status: ScriptableBridgeStatus

    private let store = ScriptableFolderStore()
    private let writer = ScriptableBridgeWriter.shared
    private var entry: OverviewEntry?
    private var courts: [CourtDay] = []
    private var listDate: Date?
    private var exportTask: Task<Void, Never>?
    private var exportPending = false

    init() {
        if (try? store.loadBookmark()) != nil {
            status = .ready(lastSuccessAt: nil)
        } else {
            status = .notConfigured
        }
    }

    var hasAuthorization: Bool {
        (try? store.loadBookmark()) != nil
    }

    var hasCourtData: Bool { courts.contains { $0.total > 0 } }

    func setEntry(_ entry: OverviewEntry) {
        self.entry = entry
        scheduleExport()
    }

    func setCourts(_ days: [CourtDay], listDate: Date?) {
        courts = days
        self.listDate = listDate
        scheduleExport()
    }

    func authorize(folder: URL) {
        status = .writing(lastSuccessAt: status.lastSuccessAt)
        guard folder.startAccessingSecurityScopedResource() else {
            status = .failed(.scopeAccessDenied, lastSuccessAt: status.lastSuccessAt)
            return
        }
        defer { folder.stopAccessingSecurityScopedResource() }

        do {
            let bookmark = try ScriptableFolderStore.bookmark(folder)
            try store.saveBookmark(bookmark)
            status = .ready(lastSuccessAt: status.lastSuccessAt)
            scheduleExport()
        } catch let error as ScriptableBridgeError {
            status = .failed(error, lastSuccessAt: status.lastSuccessAt)
        } catch {
            status = .failed(.bookmarkInvalid, lastSuccessAt: status.lastSuccessAt)
        }
    }

    func revokeAuthorization() {
        store.clearBookmark()
        status = .notConfigured
    }

    func writeNow() {
        scheduleExport()
    }

    func flush() async {
        await writeCurrent()
    }

    private func scheduleExport() {
        guard hasAuthorization, entry != nil else { return }
        exportPending = true
        guard exportTask == nil else { return }
        exportTask = Task { [weak self] in
            guard let self else { return }
            while self.exportPending {
                self.exportPending = false
                await self.writeCurrent()
            }
            self.exportTask = nil
        }
    }

    private func writeCurrent() async {
        guard let entry else { return }
        status = .writing(lastSuccessAt: status.lastSuccessAt)
        let snapshot = WidgetSnapshotBuilder.build(
            entry: entry,
            courts: courts,
            listDate: listDate,
            now: Date()
        )
        status = await writer.write(snapshot)
    }
}
