import XCTest
import Security
@testable import KotenOCR

final class KeychainHelperTests: XCTestCase {
    private let key = "test_keychain_helper_\(UUID().uuidString)"

    override func setUpWithError() throws {
        // An unsigned build (CI uses CODE_SIGNING_ALLOWED=NO) has no keychain access group.
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: key, kSecValueData as String: Data()]
        let status = SecItemAdd(probe as CFDictionary, nil)
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
        if status == errSecMissingEntitlement { throw XCTSkip("Keychain not available in an unsigned build") }
    }

    override func tearDown() {
        KeychainHelper.delete(key: key)
        super.tearDown()
    }

    func testSavedItemIsThisDeviceOnly() throws {
        KeychainHelper.save(key: key, value: "secret")
        XCTAssertEqual(KeychainHelper.load(key: key), "secret")
        XCTAssertEqual(KeychainHelper.storedAccessibility(key: key),
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }

    func testOldItemIsMigratedOnLoad() throws {
        // What older versions stored: no explicit accessibility attribute.
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: Data("old".utf8)
        ]
        XCTAssertEqual(SecItemAdd(add as CFDictionary, nil), errSecSuccess)
        XCTAssertNotEqual(KeychainHelper.storedAccessibility(key: key),
                          kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(KeychainHelper.load(key: key), "old")
        XCTAssertEqual(KeychainHelper.storedAccessibility(key: key),
                       kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }
}
