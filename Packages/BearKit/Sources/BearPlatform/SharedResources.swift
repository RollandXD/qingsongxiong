import Foundation

/// 同时服务 App 与 Widget，解析重签后实际授予的共享空间。
public struct SharedResources: Sendable {
    public enum ResourceError: Error { case missingConfiguration, containerUnavailable }
    private let groups: [String]
    private let prefix: String?
    private let keychainSuffix: String

    public init(bundle: Bundle = .main) {
        let original = bundle.object(forInfoDictionaryKey: "BearAppGroupIdentifier") as? String ?? ""
        let rewritten = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let profile = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? ProfileCapabilities.decode($0) }
        groups = (profile?.matchingGroups(original: original) ?? []) + rewritten + [original]
        prefix = profile?.identifierPrefixes.first
        keychainSuffix = bundle.object(forInfoDictionaryKey: "BearKeychainGroupSuffix") as? String ?? ""
    }

    public func containerURL() throws -> URL {
        for group in groups where !group.isEmpty {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) { return url }
        }
        #if targetEnvironment(simulator)
        // 仅供模拟器界面测试；真机绝不退回私有目录掩盖共享权限失败。
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bear-simulator", isDirectory: true)
        #else
        throw ResourceError.containerUnavailable
        #endif
    }

    public func vault(service: String) throws -> KeychainVault {
        guard !keychainSuffix.isEmpty else { throw ResourceError.missingConfiguration }
        #if targetEnvironment(simulator)
        return KeychainVault(service: service, accessGroup: nil)
        #else
        let team = try prefix ?? KeychainVault.defaultTeamPrefix(service: service)
        return KeychainVault(service: service, accessGroup: team + "." + keychainSuffix)
        #endif
    }
}
