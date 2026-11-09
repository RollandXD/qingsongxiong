import Foundation

public enum RelaySite: String, Codable, Sendable, CaseIterable { case apikeyFan }
public enum RelayEndpoint: String, Codable, Sendable, CaseIterable, Identifiable {
    case balance, usage
    public var id: String { rawValue }
    public var path: String { self == .balance ? "/user/balance" : "/v1/usage" }
}

/// 不包含凭据或任意 URL；模板只允许已审核的 origin/path。
public struct RelayAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let site: RelaySite
    public let displayName: String
    public let endpoint: RelayEndpoint
    public init(id: UUID = UUID(), sessionID: UUID = UUID(), displayName: String, endpoint: RelayEndpoint = .balance) {
        self.id = id; self.sessionID = sessionID; site = .apikeyFan
        self.displayName = displayName; self.endpoint = endpoint
    }
}

public struct RelaySnapshot: Codable, Equatable, Sendable {
    public let balances: [CurrencyBalance]
    public let isAvailable: Bool?
    public let fetchedAt: Date
    public init(balances: [CurrencyBalance], isAvailable: Bool?, fetchedAt: Date) {
        self.balances = balances; self.isAvailable = isAvailable; self.fetchedAt = fetchedAt
    }
}

public struct RelayState: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { account.id }
    public let account: RelayAccount
    public let snapshot: RelaySnapshot?
    public let failure: UsageFailure?
    public let updatedAt: Date
    public init(account: RelayAccount, snapshot: RelaySnapshot?, failure: UsageFailure? = nil, updatedAt: Date) {
        self.account = account; self.snapshot = snapshot; self.failure = failure; self.updatedAt = updatedAt
    }
}

public protocol RelayRepository: Sendable {
    func states() async throws -> [RelayState]
    /// 更新时空 key 表示保留原密钥；先验证再提交，更换失败原账户不变。
    func save(id: UUID?, name: String, endpoint: RelayEndpoint, key: String) async throws
    func refresh(_ id: UUID) async throws -> RelaySnapshot
    func delete(_ id: UUID) async throws
    func clear() async throws
}
