import AIUsageDomain
import AIUsageFeature
import Foundation
import Testing

private actor BackgroundRepository: AIUsageRepository {
    private var values: [ProviderID: ProviderState]
    private var requested: [ProviderID] = []
    private var reads = 0
    init(fetchedAt: Date?, connected: Bool = true) {
        let snapshot = fetchedAt.map { UsageSnapshot(provider: .codex, windows: [], balances: [], isAvailable: true, fetchedAt: $0) }
        values = [.codex: ProviderState(provider: .codex, sessionID: UUID(),
            connection: connected ? .connected : .disconnected, snapshot: snapshot,
            failure: nil, updatedAt: fetchedAt ?? Date())]
    }
    func state(for provider: ProviderID) async throws -> ProviderState {
        reads += 1
        return values[provider] ?? .disconnected(provider, at: Date())
    }
    func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot? { values[provider]?.snapshot }
    func refresh(_ provider: ProviderID) async throws -> UsageSnapshot {
        requested.append(provider)
        let snapshot = UsageSnapshot(provider: provider, windows: [], balances: [], isAvailable: true, fetchedAt: Date())
        values[provider] = ProviderState(provider: provider, sessionID: values[provider]?.sessionID,
            connection: .connected, snapshot: snapshot, failure: nil, updatedAt: snapshot.fetchedAt)
        return snapshot
    }
    func disconnect(_ provider: ProviderID) async throws { values[provider] = .disconnected(provider, at: Date()) }
    func requests() -> [ProviderID] { requested }
    func readCount() -> Int { reads }
}

@Test @MainActor func coldBackgroundRefreshLoadsAccountsBeforeChoosingDueProviders() async {
    let repository = BackgroundRepository(fetchedAt: Date(timeIntervalSinceNow: -600))
    var reloads = 0
    let model = AIUsageModel(repository: repository, connector: nil, onDataChange: { reloads += 1 })
    #expect(model.states.isEmpty)
    await model.refreshIfNeeded()
    #expect(await repository.requests() == [.codex])
    #expect((model.states[.codex]?.snapshot?.fetchedAt.timeIntervalSinceNow ?? -600) > -10)
    // 仅时间变化不浪费 Widget 预算；冷启动加载同时建立比较基线。
    #expect(reloads == 0)
}

@Test @MainActor func coldBackgroundRefreshFetchesConnectedAccountWithoutASnapshot() async {
    let repository = BackgroundRepository(fetchedAt: nil)
    var reloads = 0
    let model = AIUsageModel(repository: repository, connector: nil, onDataChange: { reloads += 1 })
    await model.refreshIfNeeded()
    #expect(await repository.requests() == [.codex])
    #expect(model.states[.codex]?.snapshot != nil)
    #expect(reloads == 1)
}

@Test(arguments: [true, false]) @MainActor
func backgroundRefreshSkipsFreshOrDisconnectedAccounts(connected: Bool) async {
    let repository = BackgroundRepository(fetchedAt: Date(timeIntervalSinceNow: connected ? 0 : -600), connected: connected)
    let model = AIUsageModel(repository: repository, connector: nil)
    await model.refreshIfNeeded()
    #expect(await repository.requests().isEmpty)
}

@Test @MainActor func expiredBackgroundTaskDoesNotLoadOrRequestAccounts() async {
    let repository = BackgroundRepository(fetchedAt: Date(timeIntervalSinceNow: -600))
    let model = AIUsageModel(repository: repository, connector: nil)
    let task = Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        await model.refreshIfNeeded()
    }
    await task.value
    #expect(await repository.requests().isEmpty)
    #expect(await repository.readCount() == 0)
}
