import XCTest

/// 純邏輯 test bundle 冇 app host／Keychain entitlement，所以注入 memory backend，
/// 驗證遷移、更新、刪除同失敗時保留明文；真機 Keychain 存取另需實機驗收。
private final class MemorySecretStorage: SecretStorage {
    private var values: [String: String] = [:]
    var writable = true
    var readable = true
    private func key(_ account: String, _ service: String) -> String { "\(service)/\(account)" }

    func read(account: String, service: String) throws -> String? {
        guard readable else { throw SecretStoreError.keychain(errSecInteractionNotAllowed) }
        return values[key(account, service)]
    }

    func write(_ value: String?, account: String, service: String) -> Bool {
        guard writable else { return false }
        let key = key(account, service)
        if value == nil || value?.isEmpty == true { values.removeValue(forKey: key) }
        else { values[key] = value }
        return true
    }
}

final class SecretStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var storage: MemorySecretStorage!
    private let account = "test.rosterToken"
    private let service = "com.iceninye.i-widget.tests.\(UUID().uuidString)"
    private lazy var suiteName = "SecretStoreTests.\(UUID().uuidString)"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        storage = MemorySecretStorage()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        storage = nil
        super.tearDown()
    }

    func testSaveLoadsAndDeletesWithoutUserDefaultsCopy() throws {
        XCTAssertTrue(SecretStore.save("secret-value", account: account, defaults: defaults, service: service, storage: storage))
        XCTAssertEqual(try SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "secret-value")
        XCTAssertNil(defaults.string(forKey: account))
        XCTAssertTrue(SecretStore.save(nil, account: account, defaults: defaults, service: service, storage: storage))
        XCTAssertNil(try SecretStore.load(account: account, defaults: defaults, service: service, storage: storage))
    }

    func testLegacyValueMigratesThenPlaintextIsRemoved() throws {
        defaults.set("legacy-secret", forKey: account)
        XCTAssertEqual(try SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "legacy-secret")
        XCTAssertNil(defaults.string(forKey: account))
        XCTAssertEqual(try SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "legacy-secret")
    }

    func testExistingKeychainValueAlsoClearsLegacyCopy() throws {
        XCTAssertTrue(SecretStore.save("keychain-secret", account: account, defaults: defaults, service: service, storage: storage))
        defaults.set("stale-plaintext", forKey: account)
        XCTAssertEqual(try SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "keychain-secret")
        XCTAssertNil(defaults.string(forKey: account))
    }

    func testEmptyValueDeletesSecret() throws {
        XCTAssertTrue(SecretStore.save("secret-value", account: account, defaults: defaults, service: service, storage: storage))
        XCTAssertTrue(SecretStore.save("", account: account, defaults: defaults, service: service, storage: storage))
        XCTAssertNil(try SecretStore.load(account: account, defaults: defaults, service: service, storage: storage))
    }

    func testFailedMigrationKeepsLegacyValue() throws {
        defaults.set("legacy-secret", forKey: account)
        storage.writable = false
        XCTAssertEqual(try SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "legacy-secret")
        XCTAssertEqual(defaults.string(forKey: account), "legacy-secret")
    }

    func testReadErrorIsNotTreatedAsMissingOrLegacyValue() {
        defaults.set("legacy-secret", forKey: account)
        storage.readable = false
        XCTAssertThrowsError(try SecretStore.load(account: account, defaults: defaults, service: service, storage: storage)) {
            XCTAssertEqual($0 as? SecretStoreError, .keychain(errSecInteractionNotAllowed))
        }
        XCTAssertEqual(defaults.string(forKey: account), "legacy-secret")
    }

    func testAppSettingsReadErrorBlocksBlindThreeSecretOverwrite() throws {
        XCTAssertTrue(AppSettings.saveSecrets(
            rosterToken: "roster", vpsToken: "vps", statusURL: "https://private.example/status",
            defaults: defaults, storage: storage
        ))
        storage.readable = false
        XCTAssertThrowsError(try AppSettings.secretString(AppSettings.rosterToken, defaults: defaults, storage: storage))
        XCTAssertNil(AppSettings.string(AppSettings.rosterToken, defaults: defaults, storage: storage))
        XCTAssertFalse(AppSettings.saveSecrets(
            rosterToken: "", vpsToken: "", statusURL: "", defaults: defaults, storage: storage
        ))
        storage.readable = true
        XCTAssertEqual(try AppSettings.secretString(AppSettings.rosterToken, defaults: defaults, storage: storage), "roster")
        XCTAssertEqual(try AppSettings.secretString(AppSettings.vpsToken, defaults: defaults, storage: storage), "vps")
        XCTAssertEqual(try AppSettings.secretString(AppSettings.statusURL, defaults: defaults, storage: storage), "https://private.example/status")
    }

    func testAppSettingsSecretsRoundTripUpdateAndClear() {
        XCTAssertTrue(AppSettings.saveSecrets(
            rosterToken: "roster-a", vpsToken: "vps-a", statusURL: "https://a.example/status",
            defaults: defaults, storage: storage
        ))
        XCTAssertEqual(AppSettings.string(AppSettings.rosterToken, defaults: defaults, storage: storage), "roster-a")
        XCTAssertEqual(AppSettings.string(AppSettings.vpsToken, defaults: defaults, storage: storage), "vps-a")
        XCTAssertEqual(AppSettings.string(AppSettings.statusURL, defaults: defaults, storage: storage), "https://a.example/status")

        XCTAssertTrue(AppSettings.saveSecrets(
            rosterToken: "roster-b", vpsToken: "vps-b", statusURL: "https://b.example/status",
            defaults: defaults, storage: storage
        ))
        XCTAssertEqual(AppSettings.string(AppSettings.rosterToken, defaults: defaults, storage: storage), "roster-b")
        XCTAssertEqual(AppSettings.string(AppSettings.vpsToken, defaults: defaults, storage: storage), "vps-b")
        XCTAssertEqual(AppSettings.string(AppSettings.statusURL, defaults: defaults, storage: storage), "https://b.example/status")

        XCTAssertTrue(AppSettings.saveSecrets(
            rosterToken: "", vpsToken: "", statusURL: "", defaults: defaults, storage: storage
        ))
        XCTAssertNil(AppSettings.string(AppSettings.rosterToken, defaults: defaults, storage: storage))
        XCTAssertNil(AppSettings.string(AppSettings.vpsToken, defaults: defaults, storage: storage))
        XCTAssertNil(AppSettings.string(AppSettings.statusURL, defaults: defaults, storage: storage))
    }
}
