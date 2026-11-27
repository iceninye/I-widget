import Foundation
import Security

/// 私密設定只存喺部機 Keychain；唔同步、唔備份到另一部裝置。
protocol SecretStorage: AnyObject {
    func read(account: String, service: String) -> String?
    @discardableResult
    func write(_ value: String?, account: String, service: String) -> Bool
}

private final class SystemSecretStorage: SecretStorage {
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    private func query(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read(account: String, service: String) -> String? {
        var query = query(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    func write(_ value: String?, account: String, service: String) -> Bool {
        let base = query(account: account, service: service)
        if value == nil || value?.isEmpty == true {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value!.utf8),
            kSecAttrAccessible as String: Self.accessibility,
            kSecAttrSynchronizable as String: false,
        ]
        var status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = base.merging(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}

enum SecretStore {
    private static let service = "com.iceninye.i-widget.secrets"
    private static let systemStorage = SystemSecretStorage()

    static func load(
        account: String,
        defaults: UserDefaults = .standard,
        service: String = SecretStore.service,
        storage: any SecretStorage = systemStorage
    ) -> String? {
        if let value = storage.read(account: account, service: service) {
            // 上次可能喺 Keychain 寫入成功、未黎得切刪 plaintext 之間中止。
            defaults.removeObject(forKey: account)
            return value
        }
        // 兼容舊版 UserDefaults；只有 Keychain 寫入成功先刪走明文。
        let legacy = defaults.string(forKey: account)
        guard let legacy else { return nil }
        _ = save(legacy, account: account, defaults: defaults, service: service, storage: storage)
        return storage.read(account: account, service: service) ?? legacy
    }

    @discardableResult
    static func save(
        _ value: String?,
        account: String,
        defaults: UserDefaults = .standard,
        service: String = SecretStore.service,
        storage: any SecretStorage = systemStorage
    ) -> Bool {
        guard storage.write(value, account: account, service: service) else { return false }
        defaults.removeObject(forKey: account)
        return true
    }
}
