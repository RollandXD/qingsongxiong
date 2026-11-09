import AIUsageDomain
import AIUsagePresentation
import Foundation
import Testing

private let overviewTime = Date(timeIntervalSince1970: 1_800_000_000)
private func connected(_ provider: ProviderID, used: [String: Double] = [:], available: Bool? = nil) throws -> ProviderDashboardPresentation {
    let windows = try used.sorted { $0.key < $1.key }.map { try QuotaWindow(id: $0.key, label: $0.key, usedPercent: $0.value, resetsAt: nil) }
    let state = ProviderState(provider: provider, sessionID: UUID(), connection: .connected,
 snapshot: UsageSnapshot(provider: provider, windows: windows, balances: [], isAvailable: available, fetchedAt: overviewTime),
        failure: nil, updatedAt: overviewTime)
    return ProviderDashboardPresentation(provider: provider, state: state, at: overviewTime)
}

@Test func overviewPicksTheTightestGeneralWindowAcrossProviders() throws {
    let view = DashboardOverviewPresentation(providers: [
        try connected(.codex, used: ["rate_limit.primary_window": 30]),
        try connected(.claude, used: ["five_hour": 85, "seven_day_sonnet": 99]),
    ])
    #expect(view.tightest?.provider == .claude)
    #expect(view.tightest?.window.remaining == 15)
    #expect(view.mood == .watchful)
    #expect(view.summary(at: overviewTime).hasPrefix("Claude five_hour 还剩 15%"))
}

@Test func overviewMoodEscalatesOnNearlyEmptyOrBlockedBalance() throws {
    #expect(DashboardOverviewPresentation(providers: [try connected(.codex, used: ["rate_limit.primary_window": 97])]).mood == .urgent)
    #expect(DashboardOverviewPresentation(providers: [
        try connected(.codex, used: ["rate_limit.primary_window": 10]), try connected(.deepseek, available: false),
    ]).mood == .urgent)
    #expect(DashboardOverviewPresentation(providers: [try connected(.codex, used: ["rate_limit.primary_window": 10])]).mood == .calm)
}

@Test func overviewSleepsWithoutConnectedAccounts() {
    let view = DashboardOverviewPresentation(providers: ProviderID.allCases.map {
        ProviderDashboardPresentation(provider: $0, state: nil, at: overviewTime)
    })
    #expect(view.mood == .asleep)
    #expect(view.tightest == nil)
    #expect(view.summary(at: overviewTime).contains("还没连接"))
}
