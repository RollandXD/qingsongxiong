import AIUsageDomain
import AIUsagePresentation
import Foundation
import Testing

// 2027-01-15 08:00:00 UTC，周五。
private let honeyNow = Date(timeIntervalSince1970: 1_800_000_000)
private let honeyCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func honeyWindow(_ id: String, label: String? = nil, used: Double, reset: TimeInterval? = nil) throws -> QuotaWindow {
    try QuotaWindow(id: id, label: label ?? id, usedPercent: used, resetsAt: reset.map { honeyNow.addingTimeInterval($0) })
}

private func honeyDashboard(_ provider: ProviderID, windows: [QuotaWindow] = [],
                            connection: AccountConnection = .connected) -> ProviderDashboardPresentation {
    let state = ProviderState(provider: provider, sessionID: UUID(), connection: connection,
        snapshot: connection == .connected
            ? UsageSnapshot(provider: provider, windows: windows, balances: [], isAvailable: nil, fetchedAt: honeyNow) : nil,
        failure: nil, updatedAt: honeyNow)
    return ProviderDashboardPresentation(provider: provider, state: state, at: honeyNow)
}

private func honeyHero(_ dashboards: [ProviderDashboardPresentation]) -> HeroPresentation {
    HeroPresentation(overview: DashboardOverviewPresentation(providers: dashboards),
                     jars: dashboards.map(HoneyJarPresentation.init), now: honeyNow, calendar: honeyCalendar)
}

@Test func claudeJarMatchesFiveHourAndSevenDayByExactID() throws {
    let jar = HoneyJarPresentation(honeyDashboard(.claude, windows: [
        try honeyWindow("seven_day_sonnet", used: 100, reset: 900),
        try honeyWindow("seven_day", used: 30, reset: 600),
        try honeyWindow("five_hour", used: 10, reset: 1_200),
        try honeyWindow("seven_day_opus", used: 45, reset: 900),
    ]))
    #expect(jar.provider == .claude)
    #expect(jar.fiveHour?.id == "five_hour")
    #expect(jar.weekly?.id == "seven_day")
    #expect(jar.extras.map(\.id) == ["seven_day_sonnet", "seven_day_opus"])
}

@Test func codexJarUsesWindowDurationLabelsAndKeepsCodeReviewAsExtra() throws {
    let jar = HoneyJarPresentation(honeyDashboard(.codex, windows: [
        try honeyWindow("rate_limit.primary_window", label: "5 小时", used: 28, reset: 7_200),
        try honeyWindow("rate_limit.secondary_window", label: "7 天", used: 54, reset: 172_800),
        try honeyWindow("code_review_rate_limit.primary_window", label: "代码审查 · 1 天", used: 97, reset: 36_000),
    ]))
    #expect(jar.fiveHour?.id == "rate_limit.primary_window")
    #expect(jar.weekly?.id == "rate_limit.secondary_window")
    #expect(jar.extras.map(\.id) == ["code_review_rate_limit.primary_window"])
}

@Test func codexWeeklyOnlyPlanDoesNotFakeAFiveHourWindow() throws {
    let jar = HoneyJarPresentation(honeyDashboard(.codex, windows: [
        try honeyWindow("rate_limit.primary_window", label: "7 天", used: 20, reset: 172_800),
    ]))
    #expect(jar.fiveHour == nil)
    #expect(jar.weekly?.id == "rate_limit.primary_window")
    #expect(jar.extras.isEmpty)
}

@Test func unrecognisedGeneralWindowsFallBackToResetOrder() throws {
    let jar = HoneyJarPresentation(honeyDashboard(.codex, windows: [
        try honeyWindow("rate_limit.secondary_window", label: "额度窗口", used: 40, reset: 500_000),
        try honeyWindow("rate_limit.primary_window", label: "额度窗口", used: 10, reset: 3_000),
        try honeyWindow("code_review_rate_limit.primary_window", label: "代码审查 · 额度窗口", used: 0, reset: 100),
    ]))
    #expect(jar.fiveHour?.id == "rate_limit.primary_window")
    #expect(jar.weekly?.id == "rate_limit.secondary_window")
    #expect(jar.extras.map(\.id) == ["code_review_rate_limit.primary_window"])
}

@Test func fallbackFillsOnlyTheMissingSlot() throws {
    let jar = HoneyJarPresentation(honeyDashboard(.codex, windows: [
        try honeyWindow("rate_limit.primary_window", label: "5 小时", used: 10, reset: 3_000),
        try honeyWindow("rate_limit.secondary_window", label: "额度窗口", used: 40, reset: 500_000),
    ]))
    #expect(jar.fiveHour?.id == "rate_limit.primary_window")
    #expect(jar.weekly?.id == "rate_limit.secondary_window")
    #expect(jar.extras.isEmpty)
}

@Test func jarWithoutWindowsHasNoSlots() {
    let jar = HoneyJarPresentation(honeyDashboard(.deepseek))
    #expect(jar.fiveHour == nil)
    #expect(jar.weekly == nil)
    #expect(jar.extras.isEmpty)
}

@Test func thresholdsClassifyBoundaries() {
    #expect(QuotaThresholds.level(remainingPercent: 0) == .urgent)
    #expect(QuotaThresholds.level(remainingPercent: 5) == .urgent)
    #expect(QuotaThresholds.level(remainingPercent: 5.1) == .watch)
    #expect(QuotaThresholds.level(remainingPercent: 20) == .watch)
    #expect(QuotaThresholds.level(remainingPercent: 20.1) == .normal)
}

@Test func compactCountdownBoundaries() {
    #expect(ResetCountdown.compact(0) == "1分")
    #expect(ResetCountdown.compact(59) == "1分")
    #expect(ResetCountdown.compact(8 * 60) == "8分")
    #expect(ResetCountdown.compact(3_599) == "59分")
    #expect(ResetCountdown.compact(3_600) == "1时0分")
    #expect(ResetCountdown.compact(3 * 3_600 + 12 * 60) == "3时12分")
    #expect(ResetCountdown.compact(86_400) == "1天0时")
    #expect(ResetCountdown.compact(2 * 86_400 + 23 * 3_600 + 59 * 60) == "2天23时")
    #expect(ResetCountdown.compact(-30) == "1分")
}

@Test func momentNamesTodayTomorrowAndWeekday() {
    #expect(ResetCountdown.moment(honeyNow.addingTimeInterval(12 * 3_600), now: honeyNow, calendar: honeyCalendar) == "今天 20:00")
    #expect(ResetCountdown.moment(honeyNow.addingTimeInterval(19 * 3_600 + 58 * 60), now: honeyNow, calendar: honeyCalendar) == "明天 03:58")
    // 2027-01-21 是周四。
    #expect(ResetCountdown.moment(honeyNow.addingTimeInterval(6 * 86_400 + 9 * 3_600 + 55 * 60), now: honeyNow, calendar: honeyCalendar) == "周四 17:55")
    // 2027-01-17 是周日。
    #expect(ResetCountdown.moment(honeyNow.addingTimeInterval(2 * 86_400), now: honeyNow, calendar: honeyCalendar) == "周日 08:00")
}

@Test func forecastRestoresWindowsOnlyAfterTheirReset() throws {
    let window = UsageWindowPresentation(try honeyWindow("five_hour", used: 90, reset: 3_600), provider: .claude)
    #expect(ScrubForecast.remainingPercent(window, now: honeyNow, offset: 0) == 10)
    #expect(ScrubForecast.remainingPercent(window, now: honeyNow, offset: 3_599) == 10)
    #expect(ScrubForecast.remainingPercent(window, now: honeyNow, offset: 3_600) == 100)
    #expect(ScrubForecast.remainingPercent(window, now: honeyNow, offset: 7_200) == 100)
    let unknown = UsageWindowPresentation(try honeyWindow("five_hour", used: 90), provider: .claude)
    #expect(ScrubForecast.remainingPercent(unknown, now: honeyNow, offset: 7 * 86_400) == 10)
}

@Test func forecastNeverTurnsExpiredReadingsIntoConfirmedFullQuota() throws {
    for reset in [-60.0, 0.0] {
        let window = UsageWindowPresentation(try honeyWindow("five_hour", used: 90, reset: reset), provider: .claude)
        for offset in [0.0, 3_600, -1, Double.infinity, Double.nan] {
            #expect(ScrubForecast.remainingPercent(window, now: honeyNow, offset: offset) == 10)
        }
    }
    let future = UsageWindowPresentation(try honeyWindow("five_hour", used: 90, reset: 60), provider: .claude)
    for offset in [-1.0, Double.infinity, Double.nan] {
        #expect(ScrubForecast.remainingPercent(future, now: honeyNow, offset: offset) == 10)
    }
}

@Test func resetOffsetsFilterRangeSortAndDeduplicate() throws {
    let windows = try [
        honeyWindow("a", used: 0, reset: 600),
        honeyWindow("b", used: 0, reset: -60),
        honeyWindow("c", used: 0, reset: 0),
        honeyWindow("d", used: 0, reset: 600),
        honeyWindow("e", used: 0, reset: 7 * 86_400),
        honeyWindow("f", used: 0, reset: 7 * 86_400 + 1),
        honeyWindow("g", used: 0),
        honeyWindow("h", used: 0, reset: 60),
    ].map { UsageWindowPresentation($0, provider: .claude) }
    #expect(ScrubForecast.resetOffsets(windows, now: honeyNow) == [60, 600, 7.0 * 86_400])
    #expect(ScrubForecast.resetOffsets(windows, now: honeyNow, horizon: 600) == [60, 600])
}

@Test func heroWarnsAboutTheTightestWindowWithRefillTime() throws {
    // 显式拆开算式和窗口，避免 Swift 6.2 在嵌套泛型/throws 表达式上耗尽类型推断预算。
    let weeklyReset: TimeInterval = 554_100 // 6天9时55分；固定样本，不让编译器在混合数值算式上反复推断。
    let codex = honeyDashboard(.codex, windows: [
        try honeyWindow("rate_limit.primary_window", label: "5 小时", used: 30, reset: 7_200),
        try honeyWindow("rate_limit.secondary_window", label: "7 天", used: 50, reset: 172_800),
    ])
    let claude = honeyDashboard(.claude, windows: [
        try honeyWindow("five_hour", used: 10, reset: 3_600),
        try honeyWindow("seven_day", used: 88, reset: weeklyReset),
    ])
    let hero = honeyHero([codex, claude])
    #expect(hero.lead == "Claude 周额度")
    #expect(hero.tail == "只剩 12%")
    #expect(hero.isWarning)
    #expect(hero.subtitle == "周四 17:55 回满，还要 6天9时")
}

@Test func heroIgnoresExtraWindowsAndDisconnectedProviders() throws {
    let hero = honeyHero([
        honeyDashboard(.claude, windows: [
            try honeyWindow("five_hour", used: 10, reset: 3_600),
            try honeyWindow("seven_day", used: 54, reset: 86_400),
            try honeyWindow("seven_day_sonnet", used: 100, reset: 86_400),
        ]),
        honeyDashboard(.codex, connection: .disconnected),
    ])
    #expect(hero.lead == "额度都够用")
    #expect(hero.tail.isEmpty)
    #expect(!hero.isWarning)
    #expect(hero.subtitle == "最低是 Claude 周额度 46%")
}

@Test func heroSleepsWithoutConnectedAccounts() {
    let hero = honeyHero(ProviderID.allCases.map { honeyDashboard($0, connection: .disconnected) })
    #expect(hero.lead == "还没连上账户")
    #expect(hero.tail.isEmpty)
    #expect(!hero.isWarning)
    #expect(hero.subtitle == "轻松熊先睡会儿")
}

@Test func heroSaysExhaustedAtZeroAndPicksTheEarlierResetOnTies() throws {
    let hero = honeyHero([
        honeyDashboard(.claude, windows: [
            try honeyWindow("five_hour", used: 100, reset: 3 * 3_600 + 12 * 60),
            try honeyWindow("seven_day", used: 100, reset: 86_400),
        ]),
    ])
    #expect(hero.lead == "Claude 5 小时")
    #expect(hero.tail == "用完了")
    #expect(hero.isWarning)
    #expect(hero.subtitle == "今天 11:12 回满，还要 3时12分")
}
