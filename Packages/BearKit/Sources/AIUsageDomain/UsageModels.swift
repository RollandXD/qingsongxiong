import Foundation

public enum ProviderID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case codex, claude, deepseek
    public var id: String { rawValue }
}

public struct QuotaWindow: Codable, Equatable, Sendable {
    public enum ValidationError: Error, Equatable { case invalidPercentage }
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?) throws {
        guard usedPercent.isFinite, usedPercent >= 0 else { throw ValidationError.invalidPercentage }
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double { max(0, 100 - usedPercent) }

    private enum CodingKeys: String, CodingKey { case id, label, usedPercent, resetsAt }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(String.self, forKey: .id),
                      label: values.decode(String.self, forKey: .label),
                      usedPercent: values.decode(Double.self, forKey: .usedPercent),
                      resetsAt: values.decodeIfPresent(Date.self, forKey: .resetsAt))
    }
}

public struct CurrencyBalance: Codable, Equatable, Sendable {
    public let currency: String
    public let total: Decimal
    public let granted: Decimal?
    public let toppedUp: Decimal?

    public init(currency: String, total: Decimal, granted: Decimal? = nil, toppedUp: Decimal? = nil) {
        self.currency = currency
        self.total = total
        self.granted = granted
        self.toppedUp = toppedUp
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let provider: ProviderID
    public let windows: [QuotaWindow]
    public let balances: [CurrencyBalance]
    public let isAvailable: Bool?
    public let fetchedAt: Date

    public init(provider: ProviderID, windows: [QuotaWindow], balances: [CurrencyBalance],
                isAvailable: Bool?, fetchedAt: Date) {
        self.provider = provider
        self.windows = windows
        self.balances = balances
        self.isAvailable = isAvailable
        self.fetchedAt = fetchedAt
    }
}

public enum UsageFailure: Error, Equatable, Sendable {
    case deviceVerificationRequired
    case disconnected
    case reconnectRequired
    case unavailable
    case rateLimited(retryAt: Date?)
}

public protocol AIUsageRepository: Sendable {
    func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot?
    func refresh(_ provider: ProviderID) async throws -> UsageSnapshot
    func disconnect(_ provider: ProviderID) async throws
}

public enum AIUsageRoute {
    public static func provider(components: [String]) -> ProviderID? {
        guard components.count == 2, components[0] == "provider" else { return nil }
        return ProviderID(rawValue: components[1])
    }
}
