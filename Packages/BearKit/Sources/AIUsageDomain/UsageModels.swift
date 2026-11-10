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
    /// 窗口长度（秒）。只有服务端字段或已核实的固定窗口规则才填；未知为 `nil`，
    /// 此时配速参考线安全降级为“不判断”，不按展示位置或翻译后的名称猜周期。
    public let periodSeconds: Int?
    /// `periodSeconds` 的来源，用于在界面上说明依据而不是冒充服务端精确起点。
    public let periodBasis: QuotaPeriodBasis?

    public init(id: String, label: String, usedPercent: Double, resetsAt: Date?,
                periodSeconds: Int? = nil, periodBasis: QuotaPeriodBasis? = nil) throws {
        guard usedPercent.isFinite, usedPercent >= 0 else { throw ValidationError.invalidPercentage }
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        let period = periodSeconds.flatMap { $0 > 0 ? $0 : nil }
        self.periodSeconds = period
        self.periodBasis = period == nil ? nil : (periodBasis ?? .serverReported)
    }

    public var remainingPercent: Double { max(0, 100 - usedPercent) }

    private enum CodingKeys: String, CodingKey { case id, label, usedPercent, resetsAt, periodSeconds, periodBasis }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // 旧缓存没有周期字段，必须继续可解码。
        try self.init(id: values.decode(String.self, forKey: .id),
                      label: values.decode(String.self, forKey: .label),
                      usedPercent: values.decode(Double.self, forKey: .usedPercent),
                      resetsAt: values.decodeIfPresent(Date.self, forKey: .resetsAt),
                      periodSeconds: values.decodeIfPresent(Int.self, forKey: .periodSeconds),
                      periodBasis: values.decodeIfPresent(QuotaPeriodBasis.self, forKey: .periodBasis))
    }
}

/// 窗口周期的依据。名义推导必须能说清依据，不能把猜测当成服务端精确起点。
public enum QuotaPeriodBasis: String, Codable, Equatable, Sendable {
    /// 服务端直接给出窗口时长，例如 Codex 的 `limit_window_seconds`。
    case serverReported
    /// 接口字段语义已核实的固定窗口，例如 Claude 的 `five_hour` / `seven_day*`。
    case knownWindowRule
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

public enum UsageFailure: Error, Codable, Equatable, Sendable {
    case deviceVerificationRequired
    case disconnected
    case reconnectRequired
    case unavailable
    case invalidResponse
    case invalidCredential
    case network
    case appRefreshRequired
    case authorizationTimedOut
    case authorizationRejected
    case serviceHTTP(status: Int)
    case rateLimited(retryAt: Date?)
}

public protocol AIUsageRepository: Sendable {
    func state(for provider: ProviderID) async throws -> ProviderState
    func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot?
    func refresh(_ provider: ProviderID) async throws -> UsageSnapshot
    func disconnect(_ provider: ProviderID) async throws
}

public protocol AIUsageAccountConnecting: Sendable {
    func supports(_ provider: ProviderID) -> Bool
    func connect(_ provider: ProviderID, apiKey: String?) async throws
    func cancel(_ provider: ProviderID) async
}

public enum AIUsageRoute {
    public static func provider(components: [String]) -> ProviderID? {
        guard components.count == 2, components[0] == "provider" else { return nil }
        return ProviderID(rawValue: components[1])
    }
}
