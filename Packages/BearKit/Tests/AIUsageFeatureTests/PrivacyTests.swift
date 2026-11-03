import AIUsageDomain
import AIUsageFeature
import Foundation
import Testing

private actor PrivacyRepository: AIUsageRepository {
    let failing: ProviderID?
    private var removed: Set<ProviderID> = []
    init(failing: ProviderID? = nil) { self.failing = failing }
    func state(for provider: ProviderID) async throws -> ProviderState {
        if removed.contains(provider) { return .disconnected(provider, at: Date()) }
        return ProviderState(provider: provider, sessionID: UUID(), connection: .connected,
                             snapshot: nil, failure: nil, updatedAt: Date())
    }
    func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot? { nil }
    func refresh(_ provider: ProviderID) async throws -> UsageSnapshot { throw UsageFailure.unavailable }
    func disconnect(_ provider: ProviderID) async throws {
        if provider == failing { throw UsageFailure.unavailable }
        removed.insert(provider)
    }
    func removedProviders() -> Set<ProviderID> { removed }
}

private actor PrivacyConnector: AIUsageAccountConnecting {
    private var cancelled: Set<ProviderID> = []
    nonisolated func supports(_ provider: ProviderID) -> Bool { true }
    func connect(_ provider: ProviderID, apiKey: String?) async throws { throw UsageFailure.unavailable }
    func cancel(_ provider: ProviderID) async { cancelled.insert(provider) }
    func cancelledProviders() -> Set<ProviderID> { cancelled }
}

@Test @MainActor func clearingAllFeatureDataCancelsEveryConnectionAndDropsUIState() async {
    let repository = PrivacyRepository()
    let connector = PrivacyConnector()
    let model = AIUsageModel(repository: repository, connector: connector)
    await model.loadCached()
    #expect(await model.clearLocalData())
    #expect(await repository.removedProviders() == Set(ProviderID.allCases))
    #expect(await connector.cancelledProviders() == Set(ProviderID.allCases))
    #expect(model.states.values.allSatisfy { $0.connection == .disconnected && $0.snapshot == nil })
    #expect(!model.clearing)
}

@Test @MainActor func oneRemovalFailureDoesNotSkipOtherProvidersOrClaimSuccess() async {
    let repository = PrivacyRepository(failing: .claude)
    let model = AIUsageModel(repository: repository, connector: PrivacyConnector())
    await model.loadCached()
    #expect(!(await model.clearLocalData()))
    #expect(await repository.removedProviders() == Set([ProviderID.codex, .deepseek]))
    #expect(model.states[.claude]?.connection == .connected)
    #expect(model.message != nil)
    #expect(!model.clearing)
}
