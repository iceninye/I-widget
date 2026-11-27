import Foundation

/// App 設定讀寫。私密欄位只存 device-only Keychain；一般設定先留喺 UserDefaults。
enum AppSettings {
    static let rosterToken = "settings.rosterToken"
    static let vpsToken = "settings.vpsToken"
    static let statusURL = "settings.statusURL"
    static let scriptableTheme = "settings.scriptableTheme"

    static func string(
        _ key: String,
        defaults: UserDefaults = .standard,
        storage: any SecretStorage = SecretStore.systemStorage
    ) -> String? {
        if [rosterToken, vpsToken, statusURL].contains(key) {
            // 背景讀取遇到 Keychain 錯誤時只用 nil（跳過相關網絡工作），唔好假裝係空值。
            return try? secretString(key, defaults: defaults, storage: storage)
        }
        let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value ?? "").isEmpty ? nil : value
    }

    /// 設定頁要用 throwing 入口：Keychain 讀取失敗唔可以當成「空 token」再覆寫。
    static func secretString(
        _ key: String,
        defaults: UserDefaults = .standard,
        storage: any SecretStorage = SecretStore.systemStorage
    ) throws -> String? {
        let raw = try SecretStore.load(account: key, defaults: defaults, storage: storage)
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value ?? "").isEmpty ? nil : value
    }

    @discardableResult
    static func saveSecrets(
        rosterToken: String,
        vpsToken: String,
        statusURL: String,
        defaults: UserDefaults = .standard,
        storage: any SecretStorage = SecretStore.systemStorage
    ) -> Bool {
        // 三格會一次儲存；任何一格讀唔到都唔可以由空白值推斷「用戶清空」，先阻止全部寫入。
        do {
            _ = try secretString(rosterToken, defaults: defaults, storage: storage)
            _ = try secretString(vpsToken, defaults: defaults, storage: storage)
            _ = try secretString(statusURL, defaults: defaults, storage: storage)
        } catch {
            return false
        }
        let rosterSaved = SecretStore.save(rosterToken, account: Self.rosterToken, defaults: defaults, storage: storage)
        let vpsSaved = SecretStore.save(vpsToken, account: Self.vpsToken, defaults: defaults, storage: storage)
        let urlSaved = SecretStore.save(statusURL, account: Self.statusURL, defaults: defaults, storage: storage)
        return rosterSaved && vpsSaved && urlSaved
    }

    static func loadScriptableTheme() -> WidgetTheme {
        WidgetTheme(rawValue: UserDefaults.standard.string(forKey: scriptableTheme) ?? "") ?? .classic
    }
}
