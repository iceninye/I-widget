import XCTest

/// 純邏輯 test bundle 冇 app host／Keychain entitlement，所以注入 memory backend，
/// 驗證遷移、更新、刪除同失敗時保留明文；真機 Keychain 存取另需實機驗收。
private final class MemorySecretStorage: SecretStorage {
    private var values: [String: String] = [:]
    var writable = true
    private func key(_ account: String, _ service: String) -> String { "\(service)/\(account)" }

    func read(account: String, service: String) -> String? { values[key(account, service)] }

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

    func testSaveLoadsAndDeletesWithoutUserDefaultsCopy() {
        XCTAssertTrue(SecretStore.save("secret-value", account: account, defaults: defaults, service: service, storage: storage))
        XCTAssertEqual(SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "secret-value")
        XCTAssertNil(defaults.string(forKey: account))
        XCTAssertTrue(SecretStore.save(nil, account: account, defaults: defaults, service: service, storage: storage))
        XCTAssertNil(SecretStore.load(account: account, defaults: defaults, service: service, storage: storage))
    }

    func testLegacyValueMigratesThenPlaintextIsRemoved() {
        defaults.set("legacy-secret", forKey: account)
        XCTAssertEqual(SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "legacy-secret")
        XCTAssertNil(defaults.string(forKey: account))
        XCTAssertEqual(SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "legacy-secret")
    }

    func testExistingKeychainValueAlsoClearsLegacyCopy() {
        XCTAssertTrue(SecretStore.save("keychain-secret", account: account, defaults: defaults, service: service, storage: storage))
        defaults.set("stale-plaintext", forKey: account)
        XCTAssertEqual(SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "keychain-secret")
        XCTAssertNil(defaults.string(forKey: account))
    }

    func testEmptyValueDeletesSecret() {
        XCTAssertTrue(SecretStore.save("secret-value", account: account, defaults: defaults, service: service, storage: storage))
        XCTAssertTrue(SecretStore.save("", account: account, defaults: defaults, service: service, storage: storage))
        XCTAssertNil(SecretStore.load(account: account, defaults: defaults, service: service, storage: storage))
    }

    func testFailedMigrationKeepsLegacyValue() {
        defaults.set("legacy-secret", forKey: account)
        storage.writable = false
        XCTAssertEqual(SecretStore.load(account: account, defaults: defaults, service: service, storage: storage), "legacy-secret")
        XCTAssertEqual(defaults.string(forKey: account), "legacy-secret")
    }
}
