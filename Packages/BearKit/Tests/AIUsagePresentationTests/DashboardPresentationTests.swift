import AIUsageDomain
import AIUsagePresentation
import Foundation
import Testing

private let displayTime = Date(timeIntervalSince1970: 1_800_000_000)
private func quota(_ id: String, _ used: Double) throws -> QuotaWindow {
    try QuotaWindow(id: id, label: id, usedPercent: used, resetsAt: nil)
}
private func state(_ provider: ProviderID, windows: [QuotaWindow] = [], balances: [CurrencyBalance] = [], failure: UsageFailure? = nil) -> ProviderState {
    ProviderState(provider: provider, sessionID: UUID(), connection: .connected,
        snapshot: UsageSnapshot(provider: provider, windows: windows, balances: balances, isAvailable: nil, fetchedAt: displayTime),
        failure: failure, updatedAt: displayTime)
}

@Test func codeReviewDoesNotReplaceTheGeneralAccountSummary() throws {
    let value = state(.codex, windows: [
        try quota("rate_limit.primary_window", 20), try quota("rate_limit.secondary_window", 40),
        try quota("code_review_rate_limit.primary_window", 100),
    ])
    let view = ProviderDashboardPresentation(provider: .codex, state: value, at: displayTime)
    #expect(view.summaryWindow?.id == "rate_limit.secondary_window")
    #expect(view.summaryWindow?.remaining == 60)
    #expect(view.compactWindows.count == 2)
    #expect(ProviderPresentation.headline(value.snapshot) == "剩余 60%")
}

@Test func aModelRestrictionRemainsVisibleWithoutClaimingEveryModelIsExhausted() throws {
    let view = ProviderDashboardPresentation(provider: .claude, state: state(.claude, windows: [
        try quota("five_hour", 10), try quota("seven_day", 30), try quota("seven_day_sonnet", 100),
    ]), at: displayTime)
    #expect(view.summaryWindow?.remaining == 70)
    #expect(view.windows.last?.role == .model)
    #expect(view.windows.last?.remaining == 0)
}

@Test func specificOnlyAndUnknownWindowsKeepTheirOwnLabels() throws {
    let view = ProviderDashboardPresentation(provider: .claude, state: state(.claude, windows: [try quota("future_slot", 17)]), at: displayTime)
    #expect(view.summaryWindow?.role == .other)
    #expect(view.summaryWindow?.label == "future_slot")
    #expect(view.generalWindows.isEmpty)
}

@Test func overageIsPreservedWhileTheRemainingGraphicIsBounded() throws {
    let view = UsageWindowPresentation(try quota("five_hour", 112.5), provider: .claude)
    #expect(view.remaining == 0)
    #expect(view.fraction == 0)
    #expect(view.window.usedPercent == 112.5)
}

@Test func compositionUsesExactDecimalAmounts() {
    let view = BalancePresentation(CurrencyBalance(currency: "CNY", total: Decimal(string: "128.36")!,
        granted: Decimal(string: "28.36")!, toppedUp: 100))
    #expect(view.parts?.count == 2)
    #expect(view.parts?.first?.amount == Decimal(string: "28.36"))
    #expect(abs((view.parts?.map(\.fraction).reduce(0, +) ?? 0) - 1) < 0.000001)
}

@Test func missingZeroNegativeOrInconsistentBalancePartsDoNotProduceInventedRatios() {
    for value in [
        CurrencyBalance(currency: "CNY", total: 0, granted: 0, toppedUp: 0),
        CurrencyBalance(currency: "CNY", total: 8, granted: nil, toppedUp: 8),
        CurrencyBalance(currency: "CNY", total: 8, granted: 3, toppedUp: 4),
        CurrencyBalance(currency: "CNY", total: 8, granted: -1, toppedUp: 9),
    ] { #expect(BalancePresentation(value).parts == nil) }
}

@Test func absentDataAndExhaustedDataAreDifferentStates() throws {
    let absent = ProviderDashboardPresentation(provider: .claude, state: nil, at: displayTime)
    let exhausted = ProviderDashboardPresentation(provider: .claude, state: state(.claude, windows: [try quota("five_hour", 100)]), at: displayTime)
    #expect(absent.headline == "—")
    #expect(exhausted.headline == "剩余 0%")
    #expect(!exhausted.isStale)
}

@Test func staleDataAndMultipleCurrenciesRetainTheirActualValues() {
    let balances = [CurrencyBalance(currency: "CNY", total: 12), CurrencyBalance(currency: "USD", total: 3)]
    let view = ProviderDashboardPresentation(provider: .deepseek, state: state(.deepseek, balances: balances), at: displayTime.addingTimeInterval(901))
    #expect(view.isStale)
    #expect(view.status == "旧读数")
    #expect(view.balances.map { $0.balance.currency } == ["CNY", "USD"])
    #expect(view.balances.map { $0.balance.total } == [12, 3])
}

@Test func passingAResetDateDoesNotClaimQuotaHasRecovered() throws {
    let window = UsageWindowPresentation(try QuotaWindow(id: "five_hour", label: "5 小时", usedPercent: 100,
        resetsAt: displayTime.addingTimeInterval(-1)), provider: .claude)
    #expect(window.resetLabel(at: displayTime) == "重置时间已过，等待刷新确认")
    #expect(window.remaining == 0)
    #expect(try UsageWindowPresentation(quota("five_hour", 10), provider: .claude).resetLabel(at: displayTime) == "未提供重置时间")
}
