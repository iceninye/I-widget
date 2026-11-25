import Foundation
import Security

struct ScriptableFolderStore {
    private static let service = "com.iceninye.i-widget.scriptable-folder"
    private static let account = "folder-bookmark"

    struct ResolvedBookmark {
        let url: URL
        let isStale: Bool
    }

    func loadBookmark() throws -> Data {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { throw ScriptableBridgeError.bookmarkMissing }
        guard status == errSecSuccess, let data = item as? Data else {
            throw ScriptableBridgeError.bookmarkInvalid
        }
        return data
    }

    func saveBookmark(_ data: Data) throws {
        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ScriptableBridgeError.bookmarkInvalid }

        var add = query
        attributes.forEach { add[$0.key] = $0.value }
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw ScriptableBridgeError.bookmarkInvalid
        }
    }

    func clearBookmark() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    func resolve(_ data: Data) throws -> ResolvedBookmark {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return ResolvedBookmark(url: url, isStale: isStale)
        } catch {
            throw ScriptableBridgeError.bookmarkInvalid
        }
    }

    static func bookmark(_ url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw ScriptableBridgeError.bookmarkInvalid
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
