import Foundation

actor ScriptableBridgeWriter {
    static let shared = ScriptableBridgeWriter()

    private static let lastSuccessKey = "scriptableBridge.lastSuccessAt"
    private let store = ScriptableFolderStore()
    private var pending: WidgetExport?
    private var writing = false

    func write(_ snapshot: WidgetExport) async -> ScriptableBridgeStatus {
        await enqueue(snapshot)
    }

    func lastSuccessAt() -> Date? {
        UserDefaults.standard.object(forKey: Self.lastSuccessKey) as? Date
    }

    private func enqueue(_ snapshot: WidgetExport) async -> ScriptableBridgeStatus {
        pending = snapshot
        guard !writing else { return currentStatus() }
        writing = true
        defer { writing = false }

        var result = currentStatus()
        while let next = pending {
            pending = nil
            result = await performWrite(next)
        }
        return result
    }

    private func performWrite(_ snapshot: WidgetExport) async -> ScriptableBridgeStatus {
        let previousSuccess = lastSuccessAt()
        guard !Task.isCancelled else {
            return .failed(.writeFailed("已取消。"), lastSuccessAt: previousSuccess)
        }

        let data: Data
        do {
            data = try snapshot.jsonData()
        } catch let error as ScriptableBridgeError {
            return .failed(error, lastSuccessAt: previousSuccess)
        } catch {
            return .failed(.encodingFailed, lastSuccessAt: previousSuccess)
        }

        let bookmark: Data
        do {
            bookmark = try store.loadBookmark()
        } catch let error as ScriptableBridgeError {
            return .failed(error, lastSuccessAt: previousSuccess)
        } catch {
            return .failed(.bookmarkInvalid, lastSuccessAt: previousSuccess)
        }

        let resolved: ScriptableFolderStore.ResolvedBookmark
        do {
            resolved = try store.resolve(bookmark)
        } catch let error as ScriptableBridgeError {
            return .failed(error, lastSuccessAt: previousSuccess)
        } catch {
            return .failed(.bookmarkInvalid, lastSuccessAt: previousSuccess)
        }

        guard resolved.url.startAccessingSecurityScopedResource() else {
            return .failed(.scopeAccessDenied, lastSuccessAt: previousSuccess)
        }
        defer { resolved.url.stopAccessingSecurityScopedResource() }

        if resolved.isStale {
            if let refreshed = try? ScriptableFolderStore.bookmark(resolved.url) {
                try? store.saveBookmark(refreshed)
            }
        }

        let fileURL = resolved.url.appendingPathComponent("i-widget.json", isDirectory: false)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: fileURL, options: [], error: &coordinationError) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            return .failed(mapWriteError(coordinationError), lastSuccessAt: previousSuccess)
        }
        if let writeError {
            return .failed(mapWriteError(writeError), lastSuccessAt: previousSuccess)
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: Self.lastSuccessKey)
        return .written(at: now)
    }

    private func mapWriteError(_ error: Error) -> ScriptableBridgeError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteNoPermissionError:
                return .providerUnavailable
            case NSFileWriteVolumeReadOnlyError:
                return .providerUnavailable
            default:
                break
            }
        }
        if nsError.domain == "NSFileProviderErrorDomain" {
            return .providerUnavailable
        }
        return .writeFailed(nsError.localizedDescription)
    }

    private func currentStatus() -> ScriptableBridgeStatus {
        do {
            _ = try store.loadBookmark()
            return .writing(lastSuccessAt: lastSuccessAt())
        } catch {
            return .failed((error as? ScriptableBridgeError) ?? .bookmarkInvalid, lastSuccessAt: lastSuccessAt())
        }
    }
}
