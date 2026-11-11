import AIUsageDomain
import Foundation
import Testing

private let historyNow = Date(timeIntervalSince1970: 1_800_000_000)

private func quotaEntry(_ id: String, remaining: Double) -> HistoryEntry {
    HistoryEntry(metric: .quota(windowID: id), value: .percent(remaining))
}

@Test func metricStableKeysDoNotCollideAcrossKinds() {
    #expect(UsageHistoryMetric.quota(windowID: "five_hour").stableKey == "quota:five_hour")
    #expect(UsageHistoryMetric.balance(currency: "CNY").stableKey == "balance:CNY")
    #expect(UsageHistoryMetric.quota(windowID: "CNY") != .balance(currency: "CNY"))
    #expect(!UsageHistoryMetric.quota(windowID: "five_hour").isBalance)
    #expect(UsageHistoryMetric.balance(currency: "CNY").isBalance)
}

@Test func amountKeepsDecimalPrecisionWhileChartValueIsADouble() {
    let exact = Decimal(string: "0.123456789012345678")!
    let value = HistoryValue.amount(exact)
    #expect(value.chartValue > 0)
    // 展示金额不能被浮点改写。
    let echoed = NSDecimalNumber(decimal: exact).stringValue
    #expect(Decimal(string: echoed) == exact)
}

@Test func archiveRoundTripsThroughJSON() throws {
    let relay = UUID()
    let archive = UsageHistoryArchive(sources: [
        UsageHistorySource(source: .provider(.claude), observations: [
            UsageObservation(at: historyNow, segment: 0, entries: [quotaEntry("five_hour", remaining: 80)]),
            UsageObservation(at: historyNow.addingTimeInterval(600), segment: 1,
                             entries: [quotaEntry("five_hour", remaining: 70)]),
        ]),
        UsageHistorySource(source: .relay(relay), observations: [
            UsageObservation(at: historyNow, segment: 0,
                             entries: [HistoryEntry(metric: .balance(currency: "CNY"),
                                                    value: .amount(Decimal(string: "12.34")!))]),
        ]),
    ], updatedAt: historyNow)

    let data = try JSONEncoder().encode(archive)
    let decoded = try JSONDecoder().decode(UsageHistoryArchive.self, from: data)
    #expect(decoded == archive)
    #expect(decoded.observations(for: .provider(.claude)).count == 2)
    #expect(decoded.observations(for: .relay(relay)).count == 1)
    #expect(decoded.source(.provider(.codex)) == nil)
}

@Test func seriesSkipsObservationsThatLackTheMetric() throws {
    let archive = UsageHistoryArchive(sources: [
        UsageHistorySource(source: .provider(.claude), observations: [
            UsageObservation(at: historyNow, segment: 0, entries: [quotaEntry("five_hour", remaining: 90)]),
            UsageObservation(at: historyNow.addingTimeInterval(60), segment: 0,
                             entries: [quotaEntry("seven_day", remaining: 60)]),
            UsageObservation(at: historyNow.addingTimeInterval(120), segment: 0,
                             entries: [quotaEntry("five_hour", remaining: 85)]),
        ]),
    ], updatedAt: historyNow)

    let fiveHour = archive.series(for: .provider(.claude), metric: .quota(windowID: "five_hour"))
    #expect(fiveHour.count == 2)
    #expect(fiveHour.map { $0.value(for: .quota(windowID: "five_hour")) } == [.percent(90), .percent(85)])
    // 缺口不补点：中间那条没有 five_hour。
    #expect(fiveHour[1].at.timeIntervalSince(fiveHour[0].at) == 120)

    let sonnet = archive.series(for: .provider(.claude), metric: .quota(windowID: "seven_day_sonnet"))
    #expect(sonnet.isEmpty)
}

@Test func segmentIsPartOfTheObservationNotTheMetric() throws {
    let archive = UsageHistoryArchive(sources: [
        UsageHistorySource(source: .provider(.codex), observations: [
            UsageObservation(at: historyNow, segment: 0, entries: [quotaEntry("rate_limit.primary_window", remaining: 70)]),
            UsageObservation(at: historyNow.addingTimeInterval(600), segment: 1,
                             entries: [quotaEntry("rate_limit.primary_window", remaining: 88)]),
        ]),
    ], updatedAt: historyNow)

    // 分段仍属于观测，旧点保留在归档；当前账户的查询不能混入另一账户的读数。
    let observations = archive.observations(for: .provider(.codex))
    #expect(observations.map(\.segment) == [0, 1])
    let series = archive.series(for: .provider(.codex), metric: .quota(windowID: "rate_limit.primary_window"))
    #expect(series.map(\.segment) == [1])
    #expect(series.first?.value(for: .quota(windowID: "rate_limit.primary_window")) == .percent(88))
}

@Test func archiveDecodesFromAMinimalDocument() throws {
    // 旧/手写文件缺 `revision` 也要能读，不能被 schema 版本卡死。
    let data = Data(#"{"updatedAt":0,"sources":[{"source":{"kind":"provider","provider":"codex"},"observations":[]}]}"#.utf8)
    let decoded = try JSONDecoder().decode(UsageHistoryArchive.self, from: data)
    #expect(decoded.revision == UsageHistoryArchive.schemaRevision)
    #expect(decoded.sources.count == 1)
    #expect(decoded.observations(for: .provider(.codex)).isEmpty)
}

@Test func emptyArchiveHasNoObservations() {
    let archive = UsageHistoryArchive.empty(at: historyNow)
    #expect(archive.sources.isEmpty)
    #expect(archive.observations(for: .provider(.claude)).isEmpty)
    #expect(archive.series(for: .provider(.claude), metric: .balance(currency: "USD")).isEmpty)
}

// MARK: - 归约：去重、分段、迟到写回、有界裁剪

private func observation(_ offset: TimeInterval, segment: Int = 0, _ remaining: Double,
                         window: String = "five_hour") -> UsageObservation {
    UsageObservation(at: historyNow.addingTimeInterval(offset), segment: segment,
                     entries: [quotaEntry(window, remaining: remaining)])
}

@Test func recordingAppendsInTimeOrderEvenWhenLate() throws {
    var archive = UsageHistoryArchive.empty(at: historyNow)
    archive = UsageHistoryReducer.recording(observation(600, 80), for: .provider(.claude),
                                            in: archive, now: historyNow.addingTimeInterval(600)).archive
    // 迟到写回：一条更早的观测插到前面，而不是覆盖。
    let late = UsageHistoryReducer.recording(observation(120, 90), for: .provider(.claude),
                                             in: archive, now: historyNow.addingTimeInterval(600))
    #expect(late.outcome == .appended)
    let series = late.archive.series(for: .provider(.claude), metric: .quota(windowID: "five_hour"))
    #expect(series.map(\.at) == [historyNow.addingTimeInterval(120), historyNow.addingTimeInterval(600)])
}

@Test func sameSecondRerecordReplacesInsteadOfDuplicating() throws {
    var archive = UsageHistoryArchive.empty(at: historyNow)
    archive = UsageHistoryReducer.recording(observation(600, 80), for: .provider(.claude),
                                            in: archive, now: historyNow).archive
    let again = UsageHistoryReducer.recording(observation(600.4, 70), for: .provider(.claude),
                                              in: archive, now: historyNow)
    #expect(again.outcome == .replaced)
    let series = again.archive.series(for: .provider(.claude), metric: .quota(windowID: "five_hour"))
    #expect(series.count == 1)
    #expect(series[0].value(for: .quota(windowID: "five_hour")) == .percent(70))
}

@Test func identicalRerecordChangesNothing() throws {
    var archive = UsageHistoryArchive.empty(at: historyNow)
    archive = UsageHistoryReducer.recording(observation(600, 80), for: .provider(.claude),
                                            in: archive, now: historyNow).archive
    let same = UsageHistoryReducer.recording(observation(600, 80), for: .provider(.claude),
                                             in: archive, now: historyNow)
    #expect(same.outcome == .unchanged)
    #expect(same.archive == archive)
}

@Test func differentMetricsInSameRefreshMergeIntoOneObservation() throws {
    var archive = UsageHistoryArchive.empty(at: historyNow)
    let first = UsageObservation(at: historyNow.addingTimeInterval(600), segment: 0,
                                 entries: [quotaEntry("five_hour", remaining: 80)])
    archive = UsageHistoryReducer.recording(first, for: .provider(.claude), in: archive, now: historyNow).archive
    let second = UsageObservation(at: historyNow.addingTimeInterval(600), segment: 0,
                                  entries: [quotaEntry("seven_day", remaining: 40)])
    let merged = UsageHistoryReducer.recording(second, for: .provider(.claude), in: archive, now: historyNow)
    #expect(merged.outcome == .replaced)
    let observations = merged.archive.observations(for: .provider(.claude))
    #expect(observations.count == 1)
    #expect(observations[0].metrics.count == 2)
}

@Test func observationsOlderThanRetentionAreDiscarded() throws {
    var archive = UsageHistoryArchive.empty(at: historyNow)
    archive = UsageHistoryReducer.recording(observation(600, 80), for: .provider(.claude),
                                            in: archive, now: historyNow.addingTimeInterval(600)).archive
    let ancient = UsageHistoryReducer.recording(observation(-UsageHistoryArchive.retention - 60, 50),
                                                for: .provider(.claude), in: archive,
                                                now: historyNow.addingTimeInterval(600))
    #expect(ancient.outcome == .discardedTooOld)
    #expect(ancient.archive == archive)
}

@Test func segmentAdvancesKeepOldPointsAndDisconnectTheCurve() throws {
    var archive = UsageHistoryArchive.empty(at: historyNow)
    archive = UsageHistoryReducer.recording(observation(600, 80), for: .provider(.codex),
                                            in: archive, now: historyNow).archive
    archive = UsageHistoryReducer.beginningSegment(for: .provider(.codex), in: archive,
                                                   now: historyNow.addingTimeInterval(700))
    #expect(archive.source(.provider(.codex))?.segment == 1)
    // 新账户还没取得读数时必须为空，不能短暂显示上一账户的指标和历史。
    #expect(archive.series(for: .provider(.codex), metric: .quota(windowID: "five_hour")).isEmpty)
    #expect(archive.metrics(for: .provider(.codex)).isEmpty)
    let after = UsageHistoryReducer.recording(observation(1200, 88), for: .provider(.codex),
                                              in: archive, now: historyNow.addingTimeInterval(1200))
    #expect(after.outcome == .appended)
    let observations = after.archive.observations(for: .provider(.codex))
    #expect(observations.map(\.segment) == [0, 1])
    // 旧点不被删掉或改写，但当前账户只看到自己分段的 88%。
    #expect(observations[0].value(for: .quota(windowID: "five_hour")) == .percent(80))
    let series = after.archive.series(for: .provider(.codex), metric: .quota(windowID: "five_hour"))
    #expect(series.map(\.segment) == [1])
    #expect(series.first?.value(for: .quota(windowID: "five_hour")) == .percent(88))
}

@Test func beginningSegmentOnUnknownSourceStartsAtOne() {
    let archive = UsageHistoryReducer.beginningSegment(for: .relay(UUID()),
                                                       in: .empty(at: historyNow), now: historyNow)
    #expect(archive.sources.count == 1)
    #expect(archive.sources[0].segment == 1)
    #expect(archive.sources[0].observations.isEmpty)
}

@Test func forgettingRemovesOnlyThatSource() throws {
    let relay = UUID()
    var archive = UsageHistoryArchive.empty(at: historyNow)
    archive = UsageHistoryReducer.recording(observation(600, 80), for: .provider(.claude),
                                            in: archive, now: historyNow).archive
    archive = UsageHistoryReducer.recording(observation(600, 90), for: .relay(relay),
                                            in: archive, now: historyNow).archive
    let cleared = UsageHistoryReducer.forgetting(.provider(.claude), in: archive, now: historyNow)
    #expect(cleared.observations(for: .provider(.claude)).isEmpty)
    #expect(cleared.observations(for: .relay(relay)).count == 1)
    // 不存在的来源：不动。
    #expect(UsageHistoryReducer.forgetting(.provider(.deepseek), in: archive, now: historyNow) == archive)
}

@Test func pruningDropsExpiredPointsAndKeepsSourcesAlive() throws {
    var archive = UsageHistoryArchive.empty(at: historyNow)
    archive = UsageHistoryReducer.recording(observation(600, 80), for: .provider(.claude),
                                            in: archive, now: historyNow).archive
    archive = UsageHistoryReducer.recording(observation(300, 70), for: .provider(.claude),
                                            in: archive, now: historyNow).archive
    let later = historyNow.addingTimeInterval(UsageHistoryArchive.retention + 900)
    let pruned = UsageHistoryReducer.pruned(archive, now: later)
    #expect(pruned.sources.isEmpty)
}

@Test func pruningKeepsNewestWhenOverPerSourceLimit() {
    let many = (0..<UsageHistoryArchive.sourceObservationLimit + 50).map { index in
        observation(TimeInterval(index), Double(index % 100))
    }
    let archive = UsageHistoryArchive(sources: [
        UsageHistorySource(source: .provider(.claude), observations: many),
    ], updatedAt: historyNow)
    let wellInsideRetention = historyNow.addingTimeInterval(TimeInterval(many.count))
    let pruned = UsageHistoryReducer.pruned(archive, now: wellInsideRetention)
    #expect(pruned.observations(for: .provider(.claude)).count == UsageHistoryArchive.sourceObservationLimit)
    // 保的是最新的那一批。
    #expect(pruned.observations(for: .provider(.claude)).last?.at == many.last?.at)
}

@Test func byteBudgetEventuallyTrimsHistory() {
    let many = (0..<2_000).map { index in observation(TimeInterval(index), Double(index % 100)) }
    let archive = UsageHistoryArchive(sources: [
        UsageHistorySource(source: .provider(.claude), observations: many),
    ], updatedAt: historyNow)
    let pruned = UsageHistoryReducer.pruned(archive, now: historyNow.addingTimeInterval(2_000), byteBudget: 10_000)
    #expect(UsageHistoryReducer.estimatedBytes(pruned) <= 10_000)
    #expect(!pruned.observations(for: .provider(.claude)).isEmpty)
}

@Test func metricsListKeepsFirstSeenOrderWithoutDuplicates() throws {
    var archive = UsageHistoryArchive.empty(at: historyNow)
    archive = UsageHistoryReducer.recording(UsageObservation(at: historyNow.addingTimeInterval(60), segment: 0,
        entries: [quotaEntry("seven_day", remaining: 50),
                  HistoryEntry(metric: .balance(currency: "CNY"), value: .amount(10))]),
        for: .provider(.claude), in: archive, now: historyNow).archive
    archive = UsageHistoryReducer.recording(UsageObservation(at: historyNow.addingTimeInterval(120), segment: 0,
        entries: [quotaEntry("five_hour", remaining: 80)]),
        for: .provider(.claude), in: archive, now: historyNow).archive
    #expect(archive.metrics(for: .provider(.claude)) == [.quota(windowID: "seven_day"),
                                                         .balance(currency: "CNY"),
                                                         .quota(windowID: "five_hour")])
}

@Test func rangeFilteringExcludesOlderPointsAndFutureNoise() {
    let relay = UUID()
    let archive = UsageHistoryArchive(sources: [
        UsageHistorySource(source: .relay(relay), observations: [
            observation(-25 * 3_600, 30),
            observation(-3 * 3_600, 40),
            observation(-60, 45),
            observation(600, 46),
        ]),
    ], updatedAt: historyNow)
    let day = archive.series(for: .relay(relay), metric: .quota(windowID: "five_hour"), in: .day, now: historyNow)
    #expect(day.count == 2)
    let month = archive.series(for: .relay(relay), metric: .quota(windowID: "five_hour"), in: .month, now: historyNow)
    #expect(month.count == 3)
}

@Test func rangesOnlyAdvertisedWhenHistoryIsLongEnough() {
    #expect(UsageHistoryRange.allCases.map(\.label) == ["24 小时", "7 天", "30 天"])
    #expect(!UsageHistoryRange.month.isMeaningful(historyAge: 3_600))
    #expect(UsageHistoryRange.day.isMeaningful(historyAge: 7 * 3_600))
    #expect(UsageHistoryRange.week.isMeaningful(historyAge: 2 * 86_400))
}
