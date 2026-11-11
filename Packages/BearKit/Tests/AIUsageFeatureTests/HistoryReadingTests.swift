import AIUsageDomain
import AIUsageFeature
import Foundation
import Testing

private actor FeatureHistoryRepository: AIUsageRepository {
    func state(for provider: ProviderID) async throws -> ProviderState { .disconnected(provider, at: Date()) }
    func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot? { nil }
    func refresh(_ provider: ProviderID) async throws -> UsageSnapshot { throw UsageFailure.unavailable }
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
