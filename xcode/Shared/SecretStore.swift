import Foundation
import Security

enum SecretStoreError: Error, Equatable {
    case keychain(OSStatus)
    case invalidData
}

/// 私密設定只存喺部機 Keychain；唔同步、唔備份到另一部裝置。
protocol SecretStorage: AnyObject {
    func read(account: String, service: String) throws -> String?
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

    func read(account: String, service: String) throws -> String? {
        var query = query(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData
        }
        return value
    }

    func write(_ value: String?, account: String, service: String) -> Bool {
        let base = query(account: account, service: service)
        if value == nil || value?.isEmpty == true {
            let status = SecItemDelete(base as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let updateAttributes: [String: Any] = [kSecValueData as String: Data(value!.utf8)]
        var status = SecItemUpdate(base as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            // Accessible／Synchronizable 只喺新增時設定；唔好放喺 SecItemUpdate 屬性字典。
            let addAttributes: [String: Any] = updateAttributes.merging([
                kSecAttrAccessible as String: Self.accessibility,
                kSecAttrSynchronizable as String: false,
            ]) { _, new in new }
            let item = base.merging(addAttributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
}

enum SecretStore {
    private static let service = "com.iceninye.i-widget.secrets"
    static let systemStorage: any SecretStorage = SystemSecretStorage()

    static func load(
        account: String,
        defaults: UserDefaults = .standard,
        service: String = SecretStore.service,
        storage: any SecretStorage = systemStorage
    ) throws -> String? {
        if let value = try storage.read(account: account, service: service) {
            // 上次可能喺 Keychain 寫入成功、未黎得切刪 plaintext 之間中止。
            if defaults.string(forKey: account) != nil { defaults.removeObject(forKey: account) }
            return value
        }
        // 兼容舊版 UserDefaults；只有 Keychain 寫入成功先刪走明文。
        let legacy = defaults.string(forKey: account)
        guard let legacy else { return nil }
        _ = save(legacy, account: account, defaults: defaults, service: service, storage: storage)
        return try storage.read(account: account, service: service) ?? legacy
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
