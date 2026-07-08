import Foundation
import OSLog
import Security

/// Minimal `kSecClassGenericPassword` wrapper for the Tide API-key and
/// future secrets. All entries live under the service
/// `swiss.weckherlin.tide`. Keys (account names) are caller-provided —
/// use stable strings like `"anthropic.api_key"`.
public enum KeychainHelper {
  public enum Error: Swift.Error {
    case unhandled(OSStatus)
    case encoding
  }

  private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "keychain")

  /// Store `value` under `key`. Replaces any existing entry.
  public static func set(key: String, value: String) throws {
    guard let data = value.data(using: .utf8) else { throw Error.encoding }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    let attrs: [String: Any] = [kSecValueData as String: data]

    let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    switch status {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var insert = query
      insert[kSecValueData as String] = data
      // Bind the secret to this device: it stays available after first
      // unlock (Tide can launch at login) but is excluded from encrypted
      // backups / Migration Assistant, so keys don't travel to other Macs.
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(insert as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw Error.unhandled(addStatus) }
    default:
      throw Error.unhandled(status)
    }
  }

  /// Read the stored value under `key`, or `nil` if missing.
  public static func get(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else { return nil }
      return String(data: data, encoding: .utf8)
    case errSecItemNotFound:
      return nil
    default:
      // A locked or errored keychain (e.g. errSecInteractionNotAllowed)
      // is NOT the same as "no key set" — surface it so it's diagnosable.
      log.warning("keychain get '\(key, privacy: .public)' failed: \(status)")
      return nil
    }
  }

  /// Remove the entry under `key`. No-op if it doesn't exist.
  public static func delete(key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    let status = SecItemDelete(query as CFDictionary)
    switch status {
    case errSecSuccess, errSecItemNotFound:
      break
    default:
      log.warning("keychain delete '\(key, privacy: .public)' failed: \(status)")
    }
  }

  private static let service = "swiss.weckherlin.tide"
}
