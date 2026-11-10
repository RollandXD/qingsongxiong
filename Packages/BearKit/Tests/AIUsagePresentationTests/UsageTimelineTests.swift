import AIUsageDomain
import AIUsagePresentation
import Foundation
import Testing

// 2027-01-15 08:00:00 UTC。
private let timelineNow = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3_600
private let day: TimeInterval = 86_400

private let claude = AccountRef.provider(.claude)

private func quota(_ id: String = "five_hour", percent: Double) -> HistoryEntry {
    HistoryEntry(metric: .quota(windowID: id), value: .percent(percent))
}

private func archive(_ observations: [UsageObservation], ref: AccountRef = claude) -> UsageHistoryArchive {
    UsageHistoryArchive(sources: [UsageHistorySource(source: ref, observations: observations)],
                        updatedAt: timelineNow)
}

private func timeline(_ archive: UsageHistoryArchive, metric: UsageHistoryMetric = .quota(windowID: "five_hour"),
                      range: UsageHistoryRange = .day, ref: AccountRef = claude) -> UsageTimelinePresentation {
    UsageTimelinePresentation(archive: archive, ref: ref, metric: metric, range: range,
                              now: timelineNow, metricLabel: "短期窗口")
}

@Test func emptyArchiveExplainsItselfInsteadOfShowingZero() {
    let empty = timeline(UsageHistoryArchive.empty(at: timelineNow))
    #expect(empty.isEmpty)
    #expect(empty.emptyReason == .noHistory)
    #expect(empty.yRange == nil)
    #expect(empty.emptyReason?.text.isEmpty == false)
}

@Test func pointsInsideRangeKeepOrderAndUseZeroToHundred() throws {
    let points = [3, 2, 1].map { offset in
        UsageObservation(at: timelineNow.addingTimeInterval(-Double(offset) * hour),
                         segment: 0, entries: [quota(percent: Double(offset) * 10)])
    }
    let shown = timeline(archive(points))
    #expect(shown.bands.count == 1)
    #expect(shown.pointCount == 3)
    let values = shown.bands[0].points.map(\.value)
    #expect(values == [30, 20, 10], "按时间升序，不按写入顺序")
    #expect(shown.yRange == 0...100)
    #expect(shown.unitLabel == "%")
    #expect(shown.emptyReason == nil)
    // 只有 3 小时历史，看 24 小时跨度时要提醒“还看不出全天的走势”。
    #expect(shown.gapNote?.contains("还看不出走势") == true)
}

@Test func accountSwitchBreaksTheLineInsteadOfFakingATrend() {
    let observations = [
        UsageObservation(at: timelineNow.addingTimeInterval(-2 * hour), segment: 0, entries: [quota(percent: 90)]),
        UsageObservation(at: timelineNow.addingTimeInterval(-1.9 * hour), segment: 0, entries: [quota(percent: 80)]),
        UsageObservation(at: timelineNow.addingTimeInterval(-1 * hour), segment: 1, entries: [quota(percent: 30)]),
        UsageObservation(at: timelineNow.addingTimeInterval(-0.9 * hour), segment: 1, entries: [quota(percent: 25)]),
    ]
    let shown = timeline(archive(observations))
    #expect(shown.bands.count == 2, "换了账户/密钥就断开")
    #expect(shown.bands.map(\.segment) == [0, 1])
    #expect(shown.pointCount == 4)
    #expect(shown.gapNote != nil, "断段要说明原因，不能让人以为掉过额度")
}

@Test func longSilenceInsideOneSegmentAlsoBreaksTheLine() {
    // 同一分段，但中间空了 3 天：不能画成一条缓慢下降的斜线。
    let observations = [
        UsageObservation(at: timelineNow.addingTimeInterval(-6 * 86_400), segment: 0, entries: [quota(percent: 90)]),
        UsageObservation(at: timelineNow.addingTimeInterval(-3 * 86_400), segment: 0, entries: [quota(percent: 40)]),
    ]
    let shown = timeline(archive(observations), range: .week)
    #expect(shown.bands.count == 2)
    #expect(shown.gapNote != nil)
}

@Test func denseReadingsStayInOneBand() {
    let observations = (0..<10).map { index in
        UsageObservation(at: timelineNow.addingTimeInterval(-Double(index) * 600),
                         segment: 0, entries: [quota(percent: Double(100 - index))])
    }
    let shown = timeline(archive(observations))
    #expect(shown.bands.count == 1)
    #expect(shown.gapNote?.contains("还看不出走势") == true)
}

@Test func shortHistoryShowsRealPointsButSaysTheSpanIsLongerThanTheHistory() {
    // 只有 2 小时历史却看 30 天：点是真的，照画；但不假装已经看出 30 天的走势。
    let observations = [
        UsageObservation(at: timelineNow.addingTimeInterval(-2 * hour), segment: 0,
                         entries: [quota(percent: 60)]),
        UsageObservation(at: timelineNow.addingTimeInterval(-hour), segment: 0,
                         entries: [quota(percent: 50)]),
    ]
    let shown = timeline(archive(observations), range: .month)
    #expect(shown.pointCount == 2)
    #expect(shown.emptyReason == nil)
    let note = try? #require(shown.gapNote)
    #expect(note?.contains("还看不出走势") == true)
}

@Test func shortHistoryWithNothingInRangeSaysHistoryIsTooShort() {
    // 有历史但都在跨度之外，且历史本身还短：说“历史不够长”，而不是“没数据”。
    let observations = [
        UsageObservation(at: timelineNow.addingTimeInterval(-50 * day), segment: 0,
                         entries: [quota(percent: 60)]),
    ]
    let shown = timeline(archive(observations), range: .day)
    #expect(shown.isEmpty)
    #expect(shown.emptyReason == .noPointsInRange,
            "历史里确实有数据，只是这个跨度没有；不能谎称从未记录过")
}

@Test func longEnoughHistoryWithNoPointsInRangeSaysSo() {
    // 历史很长，但今天这段没有读数：这是“这个跨度里没有点”，不是“历史太短”。
    let observations = [
        UsageObservation(at: timelineNow.addingTimeInterval(-20 * day), segment: 0, entries: [quota(percent: 70)]),
        UsageObservation(at: timelineNow.addingTimeInterval(-19 * day), segment: 0, entries: [quota(percent: 60)]),
    ]
    let shown = timeline(archive(observations), range: .day)
    #expect(shown.emptyReason == .noPointsInRange)
}

@Test func balanceTimelineUsesItsOwnScaleAndUnit() throws {
    let observations = [
        UsageObservation(at: timelineNow.addingTimeInterval(-2 * hour), segment: 0,
                         entries: [HistoryEntry(metric: .balance(currency: "USD"), value: .amount(12.5))]),
        UsageObservation(at: timelineNow.addingTimeInterval(-hour), segment: 0,
                         entries: [HistoryEntry(metric: .balance(currency: "USD"), value: .amount(9.25))]),
    ]
    let shown = timeline(archive(observations), metric: .balance(currency: "USD"))
    #expect(shown.isBalance)
    #expect(shown.unitLabel == "USD")
    let range = try #require(shown.yRange)
    #expect(range.upperBound >= 12.5)
    #expect(range.lowerBound <= 9.25, "金额图要框住真实区间，不能像百分比那样固定 0–100")
}

@Test func metricOptionsComeFromHistoryNotFromHardcodedProviders() {
    let metrics: [UsageHistoryMetric] = [.quota(windowID: "five_hour"), .quota(windowID: "weekly"),
                                         .balance(currency: "USD")]
    let options = UsageHistoryOptionBuilder.options(for: metrics,
                                                    labels: ["weekly": "周额度（7 天）"])
    #expect(options.map(\.label) == ["短期窗口", "周额度（7 天）", "USD 余额"])
    #expect(options.map(\.id) == metrics.map(\.stableKey))
    #expect(Set(options.map(\.id)).count == 3)
}

@Test func metricLabelFallsBackWhenCustomLabelIsEmpty() {
    #expect(UsageHistoryOptionBuilder.label(for: .quota(windowID: "weekly"), labels: ["weekly": ""]) == "周窗口")
    #expect(UsageHistoryOptionBuilder.label(for: .quota(windowID: "other")) == "短期窗口")
}

@Test func unknownAccountShowsNoHistoryRatherThanAnotherAccountsData() {
    let observations = [UsageObservation(at: timelineNow.addingTimeInterval(-hour), segment: 0,
                                        entries: [quota(percent: 50)])]
    let other = AccountRef.relay(UUID())
    let shown = timeline(archive(observations), ref: other)
    #expect(shown.isEmpty)
    #expect(shown.emptyReason == .noHistory)
}
