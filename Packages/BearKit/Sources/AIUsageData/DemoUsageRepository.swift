#if DEBUG
import AIUsageDomain
import Foundation

/// 仅供 Debug 模拟器演示注入；不访问网络、文件或用户钥匙串。
public actor DemoUsageRepository: AIUsageRepository, AIUsageAccountConnecting {
    private var values: [ProviderID: ProviderState]
    private let scenario: String
    private var count = 0
    public init(scenario: String = "normal") {
        self.scenario = scenario
        values = Self.fixtures(scenario: scenario)
    }
    public nonisolated func supports(_ provider: ProviderID) -> Bool { true }
    public func state(for provider: ProviderID) async throws -> ProviderState { values[provider]! }
    public func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot? { values[provider]?.snapshot }
    public func allStates() -> [ProviderState] { ProviderID.allCases.compactMap { values[$0] } }
    public func refresh(_ provider: ProviderID) async throws -> UsageSnapshot {
        try await Task.sleep(for: .milliseconds(420))
        try Task.checkCancellation()
        guard let old = values[provider], old.connection == .connected else { throw UsageFailure.disconnected }
        if scenario == "stale" || scenario == "missing" || (scenario == "partial" && provider == .claude) {
            let failure: UsageFailure = scenario == "missing" ? .invalidResponse : .network
            values[provider] = ProviderState(provider: provider, sessionID: old.sessionID, connection: .connected,
                snapshot: old.snapshot, failure: failure, updatedAt: Date())
            throw failure
        }
        count += 1
        let sample = Self.fixtures(scenario: scenario, step: count)[provider]!.snapshot!
        values[provider] = ProviderState(provider: provider, sessionID: old.sessionID, connection: .connected,
            snapshot: sample, failure: nil, updatedAt: Date())
        return sample
    }
    public func connect(_ provider: ProviderID, apiKey: String?) async throws {
        values[provider] = Self.fixtures(scenario: "normal")[provider]
    }
    public func cancel(_ provider: ProviderID) async {}
    public func disconnect(_ provider: ProviderID) async throws { values[provider] = .disconnected(provider, at: Date()) }

    private static func fixtures(scenario: String, step: Int = 0) -> [ProviderID: ProviderState] {
        let date = Date().addingTimeInterval(scenario == "stale" || scenario == "reconnect" ? -1800 : 0)
        let exhausted = scenario == "exhausted"
        func window(_ id: String, _ label: String, _ used: Double, reset: TimeInterval) -> QuotaWindow {
            try! QuotaWindow(id: id, label: label, usedPercent: exhausted ? 100 : max(0, used + Double(step % 5) * 2),
                             resetsAt: date.addingTimeInterval(reset))
        }
        let snapshots = [
            UsageSnapshot(provider: .codex,
                windows: [window("rate_limit.primary_window", "5 小时", 28, reset: 7200),
                          window("rate_limit.secondary_window", "7 天", 54, reset: 172800),
                          window("code_review_rate_limit.primary_window", "代码审查 · 1 天", 97, reset: 36000)],
                balances: [], isAvailable: nil, fetchedAt: date),
            UsageSnapshot(provider: .claude,
                windows: [window("five_hour", "5 小时", 21, reset: 5400),
                          window("seven_day", "7 天 · 全部模型", 88, reset: 259200),
                          window("seven_day_opus", "7 天 · Opus", 45, reset: 259200),
                          window("seven_day_sonnet", "7 天 · Sonnet", 100, reset: 259200)],
                balances: [], isAvailable: nil, fetchedAt: date),
            UsageSnapshot(provider: .deepseek, windows: [],
                balances: [CurrencyBalance(currency: "CNY", total: exhausted ? 0 : Decimal(string: "128.36")!,
                                           granted: exhausted ? 0 : Decimal(string: "28.36")!, toppedUp: exhausted ? 0 : 100)]
                    + (scenario == "multi-currency" ? [CurrencyBalance(currency: "USD", total: 8, granted: 3, toppedUp: 5)] : []),
                isAvailable: !exhausted, fetchedAt: date),
        ]
        return Dictionary(uniqueKeysWithValues: snapshots.map { snapshot in
            let provider = snapshot.provider
            if scenario == "unconnected" { return (provider, ProviderState.disconnected(provider, at: date)) }
            return (provider, ProviderState(provider: provider, sessionID: UUID(),
                connection: scenario == "reconnect" ? .reconnectRequired : .connected,
                snapshot: scenario == "missing" ? nil : snapshot,
                failure: scenario == "stale" ? .network : scenario == "missing" ? .invalidResponse : nil, updatedAt: date))
        })
    }
}
#endif
