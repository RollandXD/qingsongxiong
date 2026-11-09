import AIUsageDomain
import AIUsagePresentation
import Foundation
import Testing

@Test func resetTimelineSortsDatesAndOmitsUnknownTimes() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let windows = try [
        QuotaWindow(id: "seven_day", label: "周额度", usedPercent: 40, resetsAt: date + 600),
        QuotaWindow(id: "unknown", label: "未提供时间", usedPercent: 10, resetsAt: nil),
        QuotaWindow(id: "five_hour", label: "短窗口", usedPercent: 80, resetsAt: date + 60),
        QuotaWindow(id: "seven_day_sonnet", label: "Sonnet", usedPercent: 0, resetsAt: date + 600),
    ]
    let state = ProviderState(provider: .claude, sessionID: UUID(), connection: .connected,
        snapshot: UsageSnapshot(provider: .claude, windows: windows, balances: [], isAvailable: nil, fetchedAt: date),
        failure: nil, updatedAt: date)
    let view = ProviderDashboardPresentation(provider: .claude, state: state, at: date)
    #expect(view.resetTimeline.map(\.id) == ["five_hour", "seven_day", "seven_day_sonnet"])
    // 时间轴不改变用量窗口的展示顺序或摘要选择。
    #expect(view.windows.map(\.id) == windows.map(\.id))
    #expect(view.summaryWindow?.id == "five_hour")
}
