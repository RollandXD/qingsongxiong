import BearFoundation
import Foundation
import Security

public struct KeychainVault: SecureValueStore {
    public struct KeychainError: Error, Sendable { public let status: OSStatus }
    private let service: String
    private let accessGroup: String?

    public init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func query(key: String) -> [String: Any] {
        var result: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        if let accessGroup { result[kSecAttrAccessGroup as String] = accessGroup }
        return result
    }

    public func read(key: String) throws -> Data? {
        var request = query(key: key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return data
    }

    public func write(_ data: Data, key: String) throws {
        let request = query(key: key)
        let updated = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeychainError(status: updated) }
        var addition = request
        addition[kSecValueData as String] = data
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(addition as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func remove(key: String) throws {
        let status = SecItemDelete(query(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    /// 从系统返回的默认访问组解析签名团队，不硬编码作者的 Team ID。
    public static func defaultTeamPrefix(service: String) throws -> String {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service + ".bootstrap",
                                   kSecAttrAccount as String: "prefix-probe"]
        var request = base
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        var status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound {
            var addition = base
            addition[kSecValueData as String] = Data([1])
            addition[kSecReturnAttributes as String] = true
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(addition as CFDictionary, &result)
        }
        guard status == errSecSuccess,
              let attributes = result as? [String: Any],
              let group = attributes[kSecAttrAccessGroup as String] as? String,
              let prefix = group.split(separator: ".").first, !prefix.isEmpty else {
            throw KeychainError(status: status == errSecSuccess ? errSecDecode : status)
        }
        return String(prefix)
    }
}
