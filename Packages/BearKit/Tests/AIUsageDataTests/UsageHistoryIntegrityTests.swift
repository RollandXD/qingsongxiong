import AIUsageData
import AIUsageDomain
import BearFoundation
import Foundation
import Testing

private struct IntegrityClock: BearClock {
    let instant: Date
    func now() -> Date { instant }
}
private let integrityNow = Date(timeIntervalSince1970: 1_800_000_000)
private func integrityContainer() throws -> URL {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("history-integrity-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    return path
}
private func integrityService(_ root: URL) throws -> UsageHistoryService {
    try UsageHistoryService(container: root, clock: IntegrityClock(instant: integrityNow))
}

@Test func providerSnapshotRecordsDeepSeekBalancesIncludingNegativeAndExactAmounts() async throws {
    let root = try integrityContainer()
    defer { try? FileManager.default.removeItem(at: root) }
    let history = try integrityService(root)
    let exact = Decimal(string: "-12.34567890123456789")!
    let snapshot = UsageSnapshot(provider: .deepseek, windows: [],
        balances: [CurrencyBalance(currency: "USD", total: exact), CurrencyBalance(currency: "CNY", total: 4)],
        isAvailable: true, fetchedAt: integrityNow)
    try await history.record(snapshot: snapshot, for: .provider(.deepseek))
    let rows = try await history.archive().observations(for: .provider(.deepseek))
    #expect(rows.count == 1)
    #expect(rows.first?.value(for: .balance(currency: "USD")) == .amount(exact))
    #expect(rows.first?.value(for: .balance(currency: "CNY")) == .amount(4))
}

@Test func unknownEnvelopeOrHistoryRevisionIsPreservedByteForByte() async throws {
    struct Envelope: Encodable { let schemaVersion: Int; let record: UsageHistoryArchive }
    for (envelope, revision) in [(99, 1), (1, 99)] {
        let root = try integrityContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("ai-usage-history")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("snapshot.json")
        let original = try JSONEncoder().encode(Envelope(schemaVersion: envelope,
            record: UsageHistoryArchive(sources: [], updatedAt: integrityNow, revision: revision)))
        try original.write(to: file)
        let history = try integrityService(root)
        await #expect(throws: UsageHistoryFailure.self) { try await history.archive() }
        await #expect(throws: UsageHistoryFailure.self) {
            try await history.record(balances: [CurrencyBalance(currency: "USD", total: 5)],
                                     at: integrityNow, for: .provider(.deepseek))
        }
        #expect(try Data(contentsOf: file) == original)
    }
}

@Test func failedHistoryWriteRemainsVisibleAndCanRetryWithoutLosingTheObservation() async throws {
    let root = try integrityContainer()
    defer { try? FileManager.default.removeItem(at: root) }
    let history = try integrityService(root)
    _ = try await history.archive()
    let lock = root.appendingPathComponent("ai-usage-history/snapshot.lock")
    try FileManager.default.removeItem(at: lock)
    try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
    await #expect(throws: UsageHistoryFailure.self) {
        try await history.record(balances: [CurrencyBalance(currency: "USD", total: 7)],
                                 at: integrityNow, for: .provider(.deepseek))
    }
    await #expect(throws: UsageHistoryFailure.self) { try await history.archive() }
    try FileManager.default.removeItem(at: lock)
    let restored = try await history.archive()
    #expect(restored.series(for: .provider(.deepseek), metric: .balance(currency: "USD")).count == 1)
    let restarted = try integrityService(root)
    #expect(try await restarted.archive() == restored)
}

@Test func failedPrivacyRemovalCannotPretendThatTheLastSourceWasDeleted() async throws {
    let root = try integrityContainer()
    defer { try? FileManager.default.removeItem(at: root) }
    let history = try integrityService(root)
    try await history.record(balances: [CurrencyBalance(currency: "USD", total: 7)],
                             at: integrityNow, for: .provider(.deepseek))
    let lock = root.appendingPathComponent("ai-usage-history/snapshot.lock")
    let file = root.appendingPathComponent("ai-usage-history/snapshot.json")
    try FileManager.default.removeItem(at: lock)
    try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
    await #expect(throws: UsageHistoryFailure.self) { try await history.forget(.provider(.deepseek)) }
    #expect(FileManager.default.fileExists(atPath: file.path))
    try FileManager.default.removeItem(at: lock)
    try await history.forget(.provider(.deepseek))
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(try await history.archive().sources.isEmpty)
}

@Test func sharedActorAcceptsProviderAndRelayObservationsWithoutOverwritingEither() async throws {
    let root = try integrityContainer()
    defer { try? FileManager.default.removeItem(at: root) }
    let history = try integrityService(root)
    let relay = UUID()
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            try await history.record(balances: [CurrencyBalance(currency: "USD", total: 5)],
                                     at: integrityNow, for: .relay(relay))
        }
        group.addTask {
            try await history.record(balances: [CurrencyBalance(currency: "CNY", total: 8)],
                                     at: integrityNow, for: .provider(.deepseek))
        }
        try await group.waitForAll()
    }
    #expect(try await history.archive().sources.count == 2)
}

@Test func unavailableHistoryServiceReportsFailureInsteadOfAnEmptyArchive() async {
    let history = UnavailableUsageHistory()
    await #expect(throws: UsageHistoryFailure.self) { try await history.archive() }
    await #expect(throws: UsageHistoryFailure.self) { try await history.forgetAll() }
}
