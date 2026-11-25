import Foundation

enum ScriptableBridgeError: LocalizedError, Equatable {
    case notConfigured
    case bookmarkMissing
    case bookmarkInvalid
    case scopeAccessDenied
    case providerUnavailable
    case coordinationConflict
    case encodingFailed
    case writeFailed(String)
    case payloadTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "未選擇 Scriptable 資料夾。"
        case .bookmarkMissing:
            return "未有資料夾授權，請重新選擇。"
        case .bookmarkInvalid:
            return "資料夾授權已失效，請重新選擇。"
        case .scopeAccessDenied:
            return "無法存取已授權資料夾。"
        case .providerUnavailable:
            return "iCloud／File Provider 暫時不可用。"
        case .coordinationConflict:
            return "檔案正在同步，請稍後再試。"
        case .encodingFailed:
            return "無法編碼 Widget JSON。"
        case .writeFailed(let message):
            return "寫入失敗：\(message)"
        case .payloadTooLarge(let bytes):
            return "Widget JSON 過大（\(bytes) bytes）。"
        }
    }

    var needsReauthorization: Bool {
        self == .bookmarkMissing || self == .bookmarkInvalid
    }
}

struct ScriptableBridgeStatus: Equatable {
    enum State: Equatable {
        case notConfigured
        case ready
        case writing
        case writtenAwaitingCloud
        case failed
        case needsReauthorization
    }

    let state: State
    let message: String
    let lastSuccessAt: Date?

    static let notConfigured = ScriptableBridgeStatus(
        state: .notConfigured,
        message: "未選擇 Scriptable 資料夾。",
        lastSuccessAt: nil
    )

    static func ready(lastSuccessAt: Date?) -> ScriptableBridgeStatus {
        ScriptableBridgeStatus(
            state: .ready,
            message: "資料夾已授權，可以同步到 Scriptable。",
            lastSuccessAt: lastSuccessAt
        )
    }

    static func writing(lastSuccessAt: Date?) -> ScriptableBridgeStatus {
        ScriptableBridgeStatus(state: .writing, message: "正在寫入 i-widget.json…", lastSuccessAt: lastSuccessAt)
    }

    static func written(at date: Date) -> ScriptableBridgeStatus {
        ScriptableBridgeStatus(
            state: .writtenAwaitingCloud,
            message: "已寫入，等待 iCloud 同步；唔代表 Widget 已刷新。",
            lastSuccessAt: date
        )
    }

    static func failed(_ error: ScriptableBridgeError, lastSuccessAt: Date?) -> ScriptableBridgeStatus {
        ScriptableBridgeStatus(
            state: error.needsReauthorization ? .needsReauthorization : .failed,
            message: error.localizedDescription,
            lastSuccessAt: lastSuccessAt
        )
    }
}
