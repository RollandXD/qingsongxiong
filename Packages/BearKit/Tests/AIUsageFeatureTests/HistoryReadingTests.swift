import AIUsageDomain
import AIUsageFeature
import Foundation
import Testing

private actor FeatureHistoryRepository: AIUsageRepository {
    private let refreshSucceeds: Bool
    init(refreshSucceeds: Bool = false) { self.refreshSucceeds = refreshSucceeds }
    func state(for provider: ProviderID) async throws -> ProviderState { .disconnected(provider, at: Date()) }
    func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot? { nil }
    func refresh(_ provider: ProviderID) async throws -> UsageSnapshot {
        guard refreshSucceeds else { throw UsageFailure.unavailable }
        return UsageSnapshot(provider: provider, windows: [], balances: [], isAvailable: true, fetchedAt: Date())
    }
    func disconnect(_ provider: ProviderID) async throws {}
}

private actor HistoryReaderProbe: UsageHistoryReading {
    private var value = UsageHistoryArchive.empty(at: Date(timeIntervalSince1970: 100))
    private var failure = false
    private var holdNext: Bool
    private var pending: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    init(holdNext: Bool = false) { self.holdNext = holdNext }
    func configure(failure: Bool, at seconds: TimeInterval = 100) {
        self.failure = failure
        value = .empty(at: Date(timeIntervalSince1970: seconds))
    }
    func archive() async throws -> UsageHistoryArchive {
        let captured = value
        let fails = failure
        if holdNext {
            holdNext = false
            await withCheckedContinuation { continuation in
                pending = continuation
                started?.resume()
                started = nil
            }
        }
        if fails { throw UsageFailure.unavailable }
        return captured
    }
    func setArchive(_ archive: UsageHistoryArchive) { value = archive; failure = false }
    func waitUntilReading() async {
        if pending == nil { await withCheckedContinuation { started = $0 } }
    }
    func release() { pending?.resume(); pending = nil }
}

@Test @MainActor func historyReadFailureIsReportedAndCanBeRetried() async {
    let reader = HistoryReaderProbe()
    await reader.configure(failure: true)
    let model = AIUsageModel(repository: FeatureHistoryRepository(), connector: nil, historyReader: reader)
    await model.loadHistory()
    #expect(model.historyLoaded)
    #expect(model.historyError != nil)
    #expect(model.message == nil, "历史故障不冒充当前额度故障")
    await reader.configure(failure: false)
    await model.loadHistory()
    #expect(model.historyError == nil)
    #expect(model.history.updatedAt == Date(timeIntervalSince1970: 100))
}

@Test @MainActor func historyReadFailurePreservesPreviouslyLoadedArchive() async {
    let reader = HistoryReaderProbe()
    let model = AIUsageModel(repository: FeatureHistoryRepository(), connector: nil, historyReader: reader)
    await model.loadHistory()
    let previous = model.history
    await reader.configure(failure: true)
    await model.loadHistory()
    #expect(model.history == previous)
    #expect(model.historyError != nil)
}

@Test @MainActor func clearLocalDataDropsHistoryAndRejectsLateReadCompletion() async {
    let reader = HistoryReaderProbe(holdNext: true)
    let model = AIUsageModel(repository: FeatureHistoryRepository(), connector: nil, historyReader: reader)
    let reading = Task { await model.loadHistory() }
    await reader.waitUntilReading()
    #expect(await model.clearLocalData())
    let cleared = model.history
    await reader.release()
    await reading.value
    #expect(model.history == cleared)
    #expect(!model.historyLoaded)
    #expect(model.historyError == nil)
}

@Test @MainActor func newerHistoryReadWinsOverOlderDelayedRead() async {
    let reader = HistoryReaderProbe(holdNext: true)
    let model = AIUsageModel(repository: FeatureHistoryRepository(), connector: nil, historyReader: reader)
    let older = Task { await model.loadHistory() }
    await reader.waitUntilReading()
    await reader.configure(failure: false, at: 200)
    await model.loadHistory()
    await reader.release()
    await older.value
    #expect(model.history.updatedAt == Date(timeIntervalSince1970: 200))
    #expect(model.historyError == nil)
}

@Test @MainActor func successfulRefreshReloadsHistoryBeforeReturning() async {
    let reader = HistoryReaderProbe()
    let model = AIUsageModel(repository: FeatureHistoryRepository(refreshSucceeds: true),
                             connector: nil, historyReader: reader)
    await reader.configure(failure: false, at: 300)
    await model.refresh(.codex)
    #expect(model.historyLoaded)
    #expect(model.history.updatedAt == Date(timeIntervalSince1970: 300),
            "成功刷新立即读回历史，不能等五分钟或重启才更新图")
}

@Test @MainActor func disconnectImmediatelyDropsOnlyThatProvidersInMemoryHistory() async {
    let reader = HistoryReaderProbe()
    let sources = [ProviderID.codex, .claude].map { provider in
        UsageHistorySource(source: .provider(provider), observations: [
            UsageObservation(at: Date(), segment: 0,
                             entries: [HistoryEntry(metric: .quota(windowID: "window"), value: .percent(50))])
        ])
    }
    await reader.setArchive(UsageHistoryArchive(sources: sources, updatedAt: Date()))
    let model = AIUsageModel(repository: FeatureHistoryRepository(), connector: nil, historyReader: reader)
    await model.loadHistory()
    #expect(model.history.sources.count == 2)
    #expect(await model.disconnect(.codex))
    #expect(model.history.sources.map(\.source) == [.provider(.claude)])
}
