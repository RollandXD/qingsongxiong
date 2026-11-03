import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation

/// 仅存在于数据/授权实现层；不写入共享快照或诊断信息。
public struct ProviderCredential: Codable, Sendable {
    public let sessionID: UUID
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let accountID: String?
    public let scope: String?

    public init(sessionID: UUID = UUID(), accessToken: String, refreshToken: String? = nil,
                expiresAt: Date? = nil, accountID: String? = nil, scope: String? = nil) {
        self.sessionID = sessionID
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
        self.scope = scope
    }
}

public protocol UsageCredentialStore: Sendable {
    func load(_ provider: ProviderID) throws -> ProviderCredential?
    func save(_ credential: ProviderCredential, for provider: ProviderID) throws
    func remove(_ provider: ProviderID) throws
}

public struct SecureUsageCredentialStore: UsageCredentialStore {
    private let values: any SecureValueStore
    public init(values: any SecureValueStore) { self.values = values }
    public func load(_ provider: ProviderID) throws -> ProviderCredential? {
        guard let data = try values.read(key: "ai-usage." + provider.rawValue) else { return nil }
        return try JSONDecoder().decode(ProviderCredential.self, from: data)
    }
    public func save(_ credential: ProviderCredential, for provider: ProviderID) throws {
        try values.write(JSONEncoder().encode(credential), key: "ai-usage." + provider.rawValue)
    }
    public func remove(_ provider: ProviderID) throws { try values.remove(key: "ai-usage." + provider.rawValue) }
}

public protocol UsageStateStore: Sendable {
    func load(_ provider: ProviderID) throws -> ProviderState?
    func save(_ state: ProviderState) throws
    func remove(_ provider: ProviderID) throws
}

public struct FileUsageStateStore: UsageStateStore {
    private let container: URL
    public init(container: URL) { self.container = container }
    private func store(_ provider: ProviderID) throws -> AtomicRecordStore<ProviderState> {
        try AtomicRecordStore(container: container, namespace: "ai-usage-" + provider.rawValue)
    }
    public func load(_ provider: ProviderID) throws -> ProviderState? { try store(provider).read() }
    public func save(_ state: ProviderState) throws {
        guard try store(state.provider).write(state) else { throw UsageFailure.unavailable }
    }
    public func remove(_ provider: ProviderID) throws { try store(provider).remove() }
}
