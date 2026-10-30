import XCTest
import Security
@testable import KotenOCR

final class KeychainHelperTests: XCTestCase {
    private let key = "test_keychain_helper_\(UUID().uuidString)"

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
