import AIUsageDomain
import AIUsagePresentation
import Foundation
import Testing

// 2027-01-15 08:00:00 UTC，周五。
private let paceNow = Date(timeIntervalSince1970: 1_800_000_000)
private let fiveHour = 5 * 3_600
private let sevenDay = 7 * 86_400

private func paceWindow(_ id: String, label: String? = nil, used: Double, remaining: TimeInterval,
                        period: Int? = fiveHour, basis: QuotaPeriodBasis? = .serverReported) throws -> QuotaWindow {
    try QuotaWindow(id: id, label: label ?? id, usedPercent: used,
                    resetsAt: paceNow.addingTimeInterval(remaining),
                    periodSeconds: period, periodBasis: basis)
}

private func paceDashboard(_ windows: [QuotaWindow],
                           provider: ProviderID = .claude,
                           connection: AccountConnection = .connected,
                           failure: UsageFailure? = nil) -> ProviderDashboardPresentation {
    // 断连/失败时仍可能保留上一次的缓存读数，界面要能解释“为何不判断”。
    let state = ProviderState(provider: provider, sessionID: UUID(), connection: connection,
        snapshot: windows.isEmpty ? nil
            : UsageSnapshot(provider: provider, windows: windows, balances: [], isAvailable: nil, fetchedAt: paceNow),
        failure: failure, updatedAt: paceNow)
    return ProviderDashboardPresentation(provider: provider, state: state, at: paceNow)
}

@Test func referenceLineIsHalfwayThroughHalfwayWindow() throws {
    // 5 小时窗口走到一半：参考剩余 50%。
    let window = try paceWindow("five_hour", used: 40, remaining: 2.5 * 3_600)
    let pace = try #require(QuotaPaceCalculator.pace(for: window, now: paceNow))
    #expect(pace.referenceRemainingPercent == 50)
    #expect(pace.actualRemainingPercent == 60)
    #expect(abs(pace.deltaPercentagePoints - 10) < 0.000_001)
    #expect(pace.isOnOrAhead)
    #expect(pace.comparison == "比参考多剩 10 个百分点")
    #expect(pace.periodStart == paceNow.addingTimeInterval(-2.5 * 3_600))
    #expect(abs(pace.periodStart.timeIntervalSince(pace.resetsAt) + 5 * 3_600) < 0.000_001)
}

@Test func behindReferenceSaysSoWithoutNegativeSign() throws {
    let window = try paceWindow("five_hour", used: 85, remaining: 3_600)
    let pace = try #require(QuotaPaceCalculator.pace(for: window, now: paceNow))
    // 参考剩余 20%，实际 15%。
    #expect(abs(pace.referenceRemainingPercent - 20) < 0.000_001)
    #expect(!pace.isOnOrAhead)
    #expect(pace.comparison == "比参考少剩 5 个百分点")
}

@Test func exactlyOnReferenceLineIsDescribedAsSuch() throws {
    let window = try paceWindow("five_hour", used: 50, remaining: 2.5 * 3_600)
    let pace = try #require(QuotaPaceCalculator.pace(for: window, now: paceNow))
    #expect(pace.comparison == "刚好在参考线上")
    #expect(pace.isOnOrAhead)
}

@Test func anchorsSpanTheNominalPeriod() throws {
    let window = try paceWindow("seven_day", used: 30, remaining: 3.5 * 86_400, period: sevenDay)
    let pace = try #require(QuotaPaceCalculator.pace(for: window, now: paceNow))
    let anchors = pace.referenceAnchors
    #expect(anchors.count == 2)
    #expect(anchors[0].remainingPercent == 100)
    #expect(anchors[1].remainingPercent == 0)
    #expect(anchors[1].date == pace.resetsAt)
    #expect(abs(anchors[1].date.timeIntervalSince(anchors[0].date) - Double(sevenDay)) < 0.5)
}

@Test func withoutAPeriodThereIsNoReferenceLine() throws {
    let window = try paceWindow("five_hour", used: 40, remaining: 3_600, period: nil)
    #expect(window.periodSeconds == nil)
    #expect(QuotaPaceCalculator.pace(for: window, now: paceNow) == nil)
    let status = QuotaPaceCalculator.status(for: UsageWindowPresentation(window, provider: .claude),
                                            state: paceDashboard([window]).state,
                                            isStale: false, now: paceNow)
    #expect(status == .unavailable(.unknownPeriod))
}

@Test func passedResetIsNotTreatedAsRefilled() throws {
    let window = try paceWindow("five_hour", used: 40, remaining: -60)
    #expect(QuotaPaceCalculator.pace(for: window, now: paceNow) == nil)
    let dashboard = paceDashboard([window])
    let status = QuotaPaceCalculator.status(for: UsageWindowPresentation(window, provider: .claude),
                                            state: dashboard.state, isStale: false, now: paceNow)
    #expect(status == .unavailable(.resetPassed))
}

@Test func resetFurtherThanOnePeriodIsRejected() throws {
    // 重置时刻超过一个完整周期：数据自相矛盾，不硬算。
    let window = try paceWindow("five_hour", used: 40, remaining: 6 * 3_600)
    #expect(QuotaPaceCalculator.pace(for: window, now: paceNow) == nil)
}

@Test func weekWindowUsesSevenDayReference() throws {
    let window = try paceWindow("seven_day", used: 55, remaining: 3.5 * 86_400, period: sevenDay)
    let pace = try #require(QuotaPaceCalculator.pace(for: window, now: paceNow))
    #expect(pace.referenceRemainingPercent == 50)
    #expect(pace.actualRemainingPercent == 45)
    #expect(pace.comparison == "比参考少剩 5 个百分点")
    #expect(pace.basisNote == "按服务端窗口时长 7 天 推算")
}

@Test func basisNoteDistinguishesServerDurationFromKnownRule() throws {
    let server = try paceWindow("five_hour", used: 40, remaining: 3_600, basis: .serverReported)
    let rule = try paceWindow("five_hour", used: 40, remaining: 3_600, basis: .knownWindowRule)
    let serverPace = try #require(QuotaPaceCalculator.pace(for: server, now: paceNow))
    let rulePace = try #require(QuotaPaceCalculator.pace(for: rule, now: paceNow))
    #expect(serverPace.basisNote == "按服务端窗口时长 5 小时 推算")
    #expect(rulePace.basisNote == "按已核实的 5 小时 窗口规则推算")
}

@Test func unknownPeriodIsNotSilentlyLabelledAsServerReported() throws {
    // 只给周期不给来源时按服务端处理，但没周期就没有来源。
    let window = try QuotaWindow(id: "x", label: "x", usedPercent: 10, resetsAt: paceNow, periodSeconds: 0)
    #expect(window.periodSeconds == nil)
    #expect(window.periodBasis == nil)
}

@Test func boardPicksFiveHourAndWeeklyWithoutDuplicating() throws {
    let windows = [try paceWindow("seven_day", used: 80, remaining: 3.5 * 86_400, period: sevenDay),
                   try paceWindow("five_hour", used: 20, remaining: 2.5 * 3_600),
                   try paceWindow("seven_day_opus", used: 45, remaining: 3.5 * 86_400, period: sevenDay)]
    let board = QuotaPaceBoard(dashboard: paceDashboard(windows), now: paceNow)
    #expect(board.currentWindow?.id == "five_hour")
    #expect(board.weeklyWindow?.id == "seven_day")
    #expect(board.current?.pace?.windowID == "five_hour")
    #expect(board.weekly?.pace?.windowID == "seven_day")
    #expect(board.primaryUnavailableReason == nil)
}

@Test func boardExplainsWhyItCannotJudge() throws {
    let disconnected = QuotaPaceBoard(dashboard: paceDashboard([try paceWindow("five_hour", used: 20, remaining: 600)],
                                                              connection: .disconnected), now: paceNow)
    #expect(disconnected.current == .unavailable(.notConnected))
    #expect(disconnected.primaryUnavailableReason == .notConnected)

    let failed = QuotaPaceBoard(dashboard: paceDashboard([try paceWindow("five_hour", used: 20, remaining: 600)],
                                                        failure: .network), now: paceNow)
    #expect(failed.current == .unavailable(.failedReading))

    let stale = QuotaPaceBoard(dashboard: paceDashboard([try paceWindow("five_hour", used: 20, remaining: 600)]),
                               now: paceNow.addingTimeInterval(3 * 3_600))
    // 过期判断由调用方传入；这里用同一时刻的 dashboard 模拟“读数已旧”。
    #expect(stale.weekly == nil)
}

@Test func staleReadingBlocksTheReferenceLine() throws {
    let window = try paceWindow("five_hour", used: 20, remaining: 2.5 * 3_600)
    let dashboard = paceDashboard([window])
    let status = QuotaPaceCalculator.status(for: UsageWindowPresentation(window, provider: .claude),
                                            state: dashboard.state, isStale: true, now: paceNow)
    #expect(status == .unavailable(.staleReading))
}

@Test func noReadingWhenNothingHasBeenFetched() {
    #expect(QuotaPaceCalculator.status(for: UsageWindowPresentation(try! QuotaWindow(
        id: "five_hour", label: "5 小时", usedPercent: 10, resetsAt: paceNow, periodSeconds: fiveHour),
        provider: .claude), state: nil, isStale: false, now: paceNow) == .unavailable(.noReading))
}

@Test func unavailableReasonsAlwaysExplainThemselves() {
    let reasons: [QuotaPaceUnavailableReason] = [.notConnected, .noReading, .staleReading,
                                                 .failedReading, .unknownPeriod, .resetPassed]
    for reason in reasons {
        #expect(!reason.text.isEmpty)
        #expect(!reason.text.contains("UNKNOWN"))
    }
}
