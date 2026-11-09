import AIUsageDomain
@testable import AIUsageFeature
import Foundation
import Testing

private let reloadTime = Date(timeIntervalSince1970: 1_800_000_000)
private func state(used: Double, fetchedAt: Date) throws -> ProviderState {
    ProviderState(provider: .codex, sessionID: UUID(), connection: .connected,
           snapshot: UsageSnapshot(provider: .codex, windows: [try QuotaWindow(id: "rate_limit.primary_window", label: "5 小时", usedPercent: used, resetsAt: nil)],
       balances: [], isAvailable: nil, fetchedAt: fetchedAt),
           failure: nil, updatedAt: fetchedAt)
}

@Test func unchangedReadingsDoNotReloadWidgetsUntilTheyAgeOut() throws {
    var policy = WidgetReloadPolicy()
    #expect(policy.shouldReload([.codex: try state(used: 20, fetchedAt: reloadTime)], at: reloadTime))
    // 同样读数、仅抓取时间变化：不推送。
    #expect(!policy.shouldReload([.codex: try state(used: 20, fetchedAt: reloadTime + 300)], at: reloadTime + 300))
    // 读数变化：立即推送。
    #expect(policy.shouldReload([.codex: try state(used: 25, fetchedAt: reloadTime + 360)], at: reloadTime + 360))
    // 读数不变但距上次推送已满 10 分钟：推送一次，刷新小组件的「更新于」。
    #expect(policy.shouldReload([.codex: try state(used: 25, fetchedAt: reloadTime + 960)], at: reloadTime + 960))
}

@Test func forcedChangesAlwaysReloadWidgets() throws {
    var policy = WidgetReloadPolicy()
    let value = [ProviderID.codex: try state(used: 20, fetchedAt: reloadTime)]
    #expect(policy.shouldReload(value, at: reloadTime))
    #expect(policy.shouldReload(value, at: reloadTime + 1, force: true))
}
