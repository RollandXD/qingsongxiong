#if DEBUG
import AIUsageData
import AIUsageDomain
import Foundation
import Testing

@Test func demoHistoryUsesTheSameWindowIDsAsRealDashboardFixtures() async throws {
    let now = Date()
    let reader = DemoUsageHistoryReader(now: now)
    let archive = try await reader.archive()
    let repository = DemoUsageRepository(now: now)
    for provider in [ProviderID.codex, .claude] {
        let state = try await repository.state(for: provider)
        let ids = Set(state.snapshot?.windows.map(\.id) ?? [])
        let metrics = archive.metrics(for: .provider(provider))
        #expect(metrics.count == 2)
        for metric in metrics {
            if case .quota(let id) = metric { #expect(ids.contains(id)) }
            else { Issue.record("额度账户不应有金额指标") }
        }
    }
}

@Test func demoHistoryProvidesSeparateBalanceCurrenciesAndRelayAccount() async throws {
    let archive = try await DemoUsageHistoryReader().archive()
    let deepseek = archive.metrics(for: .provider(.deepseek))
    #expect(deepseek == [.balance(currency: "CNY"), .balance(currency: "USD")])
    let relay = AccountRef.relay(UUID(uuidString: "11111111-2222-3333-4444-555555555555")!)
    #expect(archive.metrics(for: relay) == [.balance(currency: "USD")])
    #expect(archive.observations(for: relay).count > 1)
}

@Test func demoHistoryReadErrorIsDifferentFromEmptyHistory() async throws {
    let empty = try await DemoUsageHistoryReader(scenario: "no-history").archive()
    #expect(empty.sources.isEmpty)
    do {
        _ = try await DemoUsageHistoryReader(scenario: "history-error").archive()
        Issue.record("错误场景不能伪装成空历史")
    } catch { #expect(error as? UsageFailure == .unavailable) }
}
#endif
