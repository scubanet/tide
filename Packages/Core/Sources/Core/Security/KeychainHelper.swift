import Foundation
import OSLog
import Security

/// Minimal `kSecClassGenericPassword` wrapper for the Tide API-key and
/// future secrets. All entries live under the service
/// `swiss.weckherlin.tide`. Keys (account names) are caller-provided —
/// use stable strings like `"anthropic.api_key"`.
///
/// Entries are stored in the data-protection keychain
/// (`kSecUseDataProtectionKeychain`) — the legacy file keychain ignores
/// `kSecAttrAccessible`, so device-binding would silently not apply
/// there. `get` transparently migrates entries that were written to the
/// legacy keychain by earlier Tide versions.
///
/// The data-protection keychain needs a code-signing identity
/// (application-identifier entitlement). Unsigned contexts — `swift
/// test`, ad-hoc dev builds — get `errSecMissingEntitlement` (-34018)
/// for every DP call, so availability is probed once and those contexts
/// transparently fall back to the legacy keychain.
public enum KeychainHelper {
  public enum Error: Swift.Error {
    case unhandled(OSStatus)
    case encoding
  }

  private static let log = Logger(subsystem: "swiss.weckherlin.tide", category: "keychain")

  /// Whether this process may use the data-protection keychain. Probed
  /// once with a throwaway write (reads don't surface the missing
  /// entitlement; only writes return `errSecMissingEntitlement`).
  private static let dataProtectionAvailable: Bool = {
    let account = "tide.dataprotection.probe"
    let probe: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecValueData as String: Data("probe".utf8),
      kSecUseDataProtectionKeychain as String: true,
    ]
    let status = SecItemAdd(probe as CFDictionary, nil)
    switch status {
    case errSecSuccess, errSecDuplicateItem:
      let cleanup: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecUseDataProtectionKeychain as String: true,
      ]
      SecItemDelete(cleanup as CFDictionary)
      return true
    default:
      log.warning("data-protection keychain unavailable (status \(status)) — using legacy keychain")
      return false
    }
  }()

  /// Store `value` under `key`. Replaces any existing entry.
  public static func set(key: String, value: String) throws {
    guard let data = value.data(using: .utf8) else { throw Error.encoding }
    try write(key: key, data: data, dataProtection: dataProtectionAvailable)
  }

  /// Read the stored value under `key`, or `nil` if missing.
  public static func get(key: String) -> String? {
    if let value = read(key: key, dataProtection: dataProtectionAvailable) {
      return value
    }
    guard dataProtectionAvailable else { return nil }
    // Legacy-keychain fallback: entries written before the switch to the
    // data-protection keychain. Migrate on first read — delete the legacy
    // copy only after the DP write succeeded.
    if let legacy = read(key: key, dataProtection: false) {
      do {
        try write(key: key, data: Data(legacy.utf8), dataProtection: true)
        deleteLegacy(key: key)
        log.info("migrated '\(key, privacy: .public)' to data-protection keychain")
      } catch {
        log.warning("keychain migration for '\(key, privacy: .public)' failed: \(error)")
      }
      return legacy
    }
    return nil
  }

  /// Remove the entry under `key`. No-op if it doesn't exist.
  public static func delete(key: String) {
    if dataProtectionAvailable {
      let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
        kSecUseDataProtectionKeychain as String: true,
      ]
      let status = SecItemDelete(query as CFDictionary)
      switch status {
      case errSecSuccess, errSecItemNotFound:
        break
      default:
        log.warning("keychain delete '\(key, privacy: .public)' failed: \(status)")
      }
    }
    deleteLegacy(key: key)
  }

  private static func write(key: String, data: Data, dataProtection: Bool) throws {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    if dataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }
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
      // (Only honored by the data-protection keychain.)
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(insert as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw Error.unhandled(addStatus) }
    default:
      throw Error.unhandled(status)
    }
  }

  private static func read(key: String, dataProtection: Bool) -> String? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if dataProtection {
      query[kSecUseDataProtectionKeychain as String] = true
    }
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

  private static func deleteLegacy(key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
  }

  private static let service = "swiss.weckherlin.tide"
}
