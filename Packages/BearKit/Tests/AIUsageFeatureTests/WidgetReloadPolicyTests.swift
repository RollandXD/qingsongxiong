import AIUsageDomain
@testable import AIUsageFeature
import Foundation
import Testing

private let reloadTime = Date(timeIntervalSince1970: 1_800_000_000)
private let reloadSession = UUID()
private func state(used: Double, fetchedAt: Date, sessionID: UUID = reloadSession) throws -> ProviderState {
    ProviderState(provider: .codex, sessionID: sessionID, connection: .connected,
           snapshot: UsageSnapshot(provider: .codex, windows: [try QuotaWindow(id: "rate_limit.primary_window", label: "5 小时", usedPercent: used, resetsAt: nil)],
       balances: [], isAvailable: nil, fetchedAt: fetchedAt),
           failure: nil, updatedAt: fetchedAt)
}

@Test func unchangedReadingsDoNotReloadWidgetsEvenAfterTenMinutes() throws {
    var policy = WidgetReloadPolicy()
    let first = policy.shouldReload([.codex: try state(used: 20, fetchedAt: reloadTime)], at: reloadTime)
    #expect(first)
    // 同样读数、仅抓取时间变化：不推送。
    let unchanged = policy.shouldReload([.codex: try state(used: 20, fetchedAt: reloadTime + 300)], at: reloadTime + 300)
    #expect(!unchanged)
    // 读数变化：立即推送。
    let changed = policy.shouldReload([.codex: try state(used: 25, fetchedAt: reloadTime + 360)], at: reloadTime + 360)
    #expect(changed)
    // 时间推移也不 reload；组件自行申请 15 分钟时间线。
    let aged = policy.shouldReload([.codex: try state(used: 25, fetchedAt: reloadTime + 960)], at: reloadTime + 960)
    #expect(!aged)
    let replaced = policy.shouldReload([.codex: try state(used: 25, fetchedAt: reloadTime + 961, sessionID: UUID())], at: reloadTime + 961)
    #expect(replaced)
}

@Test func forcedChangesAlwaysReloadWidgets() throws {
    var policy = WidgetReloadPolicy()
    let value = [ProviderID.codex: try state(used: 20, fetchedAt: reloadTime)]
    let first = policy.shouldReload(value, at: reloadTime)
    let forced = policy.shouldReload(value, at: reloadTime + 1, force: true)
    #expect(first)
    #expect(forced)
}
