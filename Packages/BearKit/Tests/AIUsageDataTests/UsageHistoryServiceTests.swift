import AIUsageDomain
import BearFoundation
import Foundation
import Testing

@testable import AIUsageData

private struct HistoryClock: BearClock {
    let date: Date
    func now() -> Date { date }
}

private let serviceNow = Date(timeIntervalSince1970: 1_800_000_000)

private func temporaryContainer() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("history-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func service(at date: Date = serviceNow, container: URL, budget: Int = UsageHistoryArchive.maximumBytes) throws -> UsageHistoryService {
    try UsageHistoryService(container: container, clock: HistoryClock(date: date), byteBudget: budget)
}

private func snapshot(_ windows: [(id: String, remaining: Double)], fetchedAt: Date) -> UsageSnapshot {
    let quotas = windows.compactMap { pair -> QuotaWindow? in
        try? QuotaWindow(id: pair.id, label: pair.id, usedPercent: 100 - pair.remaining,
                         resetsAt: fetchedAt.addingTimeInterval(3_600), periodSeconds: 18_000)
    }
    return UsageSnapshot(provider: .claude, windows: quotas, balances: [], isAvailable: nil, fetchedAt: fetchedAt)
}

@Test func recordingASnapshotStoresRemainingPercentPerWindow() async throws {
    let container = try temporaryContainer()
    let service = try service(container: container)
    try await service.record(snapshot: snapshot([("five_hour", remaining: 72), ("seven_day", remaining: 40)],
                                                fetchedAt: serviceNow), for: .provider(.claude))
    let archive = try await service.archive()
    let observations = archive.observations(for: .provider(.claude))
    #expect(observations.count == 1)
    #expect(observations[0].at == serviceNow)
    #expect(observations[0].value(for: .quota(windowID: "five_hour")) == .percent(72))
    #expect(observations[0].value(for: .quota(windowID: "seven_day")) == .percent(40))
}

@Test func historySurvivesARestart() async throws {
    let container = try temporaryContainer()
    do {
        let first = try service(container: container)
        try await first.record(snapshot: snapshot([("five_hour", remaining: 60)], fetchedAt: serviceNow),
                               for: .provider(.claude))
    }
    let second = try service(container: container)
    let archive = try await second.archive()
    #expect(archive.observations(for: .provider(.claude)).count == 1)
}

@Test func repeatedRefreshInTheSameSecondDoesNotDuplicatePoints() async throws {
    let container = try temporaryContainer()
    let service = try service(container: container)
    try await service.record(snapshot: snapshot([("five_hour", remaining: 80)], fetchedAt: serviceNow),
                             for: .provider(.claude))
    try await service.record(snapshot: snapshot([("five_hour", remaining: 75)],
                                                fetchedAt: serviceNow.addingTimeInterval(0.4)),
                             for: .provider(.claude))
    let observations = try await service.archive().observations(for: .provider(.claude))
    #expect(observations.count == 1)
    #expect(observations[0].value(for: .quota(windowID: "five_hour")) == .percent(75))
}

@Test func lateWriteBackLandsInTheRightPlace() async throws {
    let container = try temporaryContainer()
    let service = try service(container: container)
    try await service.record(snapshot: snapshot([("five_hour", remaining: 50)],
                                                fetchedAt: serviceNow.addingTimeInterval(600)),
                             for: .provider(.claude))
    // 一个更早抓到的快照事后才写回：插到前面，不覆盖新点。
    try await service.record(snapshot: snapshot([("five_hour", remaining: 90)],
                                                fetchedAt: serviceNow.addingTimeInterval(60)),
                             for: .provider(.claude))
    let series = try await service.archive().series(for: .provider(.claude), metric: .quota(windowID: "five_hour"))
    #expect(series.map(\.at) == [serviceNow.addingTimeInterval(60), serviceNow.addingTimeInterval(600)])
    #expect(series.map { $0.value(for: .quota(windowID: "five_hour")) } == [.percent(90), .percent(50)])
}

@Test func tooOldWriteBackIsRefusedButNotFatal() async throws {
    let container = try temporaryContainer()
    let service = try service(container: container)
    try await service.record(snapshot: snapshot([("five_hour", remaining: 50)],
                                                fetchedAt: serviceNow.addingTimeInterval(600)),
                             for: .provider(.claude))
    let tooOld = serviceNow.addingTimeInterval(-UsageHistoryArchive.retention - 3_600)
    try await service.record(snapshot: snapshot([("five_hour", remaining: 10)], fetchedAt: tooOld),
                             for: .provider(.claude))
    let observations = try await service.archive().observations(for: .provider(.claude))
    #expect(observations.count == 1)
    #expect(observations[0].value(for: .quota(windowID: "five_hour")) == .percent(50))
}

@Test func accountSwitchBreaksTheCurveInsteadOfConnectingIt() async throws {
    let container = try temporaryContainer()
    let service = try service(container: container)
    try await service.record(snapshot: snapshot([("five_hour", remaining: 30)], fetchedAt: serviceNow),
                             for: .provider(.claude))
    try await service.beginSegment(for: .provider(.claude))
    try await service.record(snapshot: snapshot([("five_hour", remaining: 95)],
                                                fetchedAt: serviceNow.addingTimeInterval(60)),
                             for: .provider(.claude))
    let series = try await service.archive().series(for: .provider(.claude), metric: .quota(windowID: "five_hour"))
    #expect(series.map(\.segment) == [0, 1])
}

@Test func forgettingAnAccountRemovesItsHistoryOnly() async throws {
    let container = try temporaryContainer()
    let service = try service(container: container)
    let relay = UUID()
    try await service.record(snapshot: snapshot([("five_hour", remaining: 30)], fetchedAt: serviceNow),
                             for: .provider(.claude))
    try await service.record(balances: [CurrencyBalance(currency: "CNY", total: 12.5)], at: serviceNow,
                             for: .relay(relay))
    try await service.forget(.provider(.claude))
    let archive = try await service.archive()
    #expect(archive.observations(for: .provider(.claude)).isEmpty)
    #expect(archive.observations(for: .relay(relay)).count == 1)
}

@Test func forgettingTheLastSourceDeletesTheFile() async throws {
    let container = try temporaryContainer()
    let service = try service(container: container)
    try await service.record(snapshot: snapshot([("five_hour", remaining: 30)], fetchedAt: serviceNow),
                             for: .provider(.deepseek))
    try await service.forget(.provider(.deepseek))
    let archive = try await service.archive()
    #expect(archive.sources.isEmpty)
    let file = container.appendingPathComponent("ai-usage-history/snapshot.json")
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func corruptArchiveSelfHealsInsteadOfBlockingTheApp() async throws {
    let container = try temporaryContainer()
    let directory = container.appendingPathComponent("ai-usage-history", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: directory.appendingPathComponent("snapshot.json"))

    let service = try service(container: container)
    let archive = try await service.archive()
    #expect(archive.sources.isEmpty)
    // 自愈之后还能继续记录。
    try await service.record(snapshot: snapshot([("five_hour", remaining: 70)], fetchedAt: serviceNow),
                             for: .provider(.claude))
    #expect(try await service.archive().observations(for: .provider(.claude)).count == 1)
}

@Test func openingPrunesExpiredObservations() async throws {
    let container = try temporaryContainer()
    do {
        let old = try service(container: container)
        try await old.record(snapshot: snapshot([("five_hour", remaining: 70)], fetchedAt: serviceNow),
                             for: .provider(.claude))
    }
    // 30 天后再打开：老点应被清掉。
    let later = try service(at: serviceNow.addingTimeInterval(UsageHistoryArchive.retention + 3_600),
                            container: container)
    let archive = try await later.archive()
    #expect(archive.sources.isEmpty)
}

@Test func balancesKeepExactDecimalAmounts() async throws {
    let container = try temporaryContainer()
    let service = try service(container: container)
    let exact = Decimal(string: "0.123456789012345678")!
    try await service.record(balances: [CurrencyBalance(currency: "USD", total: exact)],
                             at: serviceNow, for: .relay(UUID()))
    let relay = try await service.archive().sources.first?.source
    let series = try await service.archive().series(for: try #require(relay),
                                                    metric: .balance(currency: "USD"))
    #expect(series.count == 1)
    guard case .amount(let stored) = try #require(series.first?.value(for: .balance(currency: "USD"))) else {
        Issue.record("余额应存成 Decimal")
        return
    }
    #expect(stored == exact)
}

@Test func byteBudgetKeepsTheArchiveSmall() async throws {
    let container = try temporaryContainer()
    let service = try service(container: container, budget: 8_000)
    for index in 0..<400 {
        let date = serviceNow.addingTimeInterval(TimeInterval(index * 60))
        let many = (0..<4).map { ("w\($0)", Double(index % 100)) }
        try await service.record(snapshot: snapshot(many, fetchedAt: date), for: .provider(.claude))
    }
    let archive = try await service.archive()
    #expect(UsageHistoryReducer.estimatedBytes(archive) <= 8_000)
    #expect(!archive.observations(for: .provider(.claude)).isEmpty)
}

@Test func disabledRecorderHasNoSideEffects() async throws {
    let disabled = DisabledUsageHistory()
    try await disabled.record(snapshot: snapshot([("five_hour", remaining: 10)], fetchedAt: serviceNow),
                              for: .provider(.claude))
    try await disabled.beginSegment(for: .provider(.claude))
    try await disabled.forget(.provider(.claude))
    #expect(try await disabled.archive().sources.isEmpty)
}
