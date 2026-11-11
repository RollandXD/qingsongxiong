import AIUsageData
import AIUsageDomain
import BearFoundation
import Foundation
import Testing

private let repositoryTime = Date(timeIntervalSince1970: 1_800_000_000)
private struct RepositoryClock: BearClock { func now() -> Date { repositoryTime } }

private final class MemoryCredentials: UsageCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProviderID: ProviderCredential] = [:]
    func load(_ provider: ProviderID) throws -> ProviderCredential? { lock.withLock { values[provider] } }
    func save(_ credential: ProviderCredential, for provider: ProviderID) throws { lock.withLock { values[provider] = credential } }
    func remove(_ provider: ProviderID) throws { lock.withLock { values[provider] = nil } }
}

private final class MemoryStates: UsageStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ProviderID: ProviderState] = [:]
    func load(_ provider: ProviderID) throws -> ProviderState? { lock.withLock { values[provider] } }
    func save(_ state: ProviderState) throws { lock.withLock { values[state.provider] = state } }
    func remove(_ provider: ProviderID) throws { lock.withLock { values[provider] = nil } }
}

private func snapshot(_ provider: ProviderID, at date: Date = repositoryTime) -> UsageSnapshot {
    UsageSnapshot(provider: provider, windows: [], balances: [], isAvailable: nil, fetchedAt: date)
}

private struct RejectingStateWrites: UsageStateStore {
    let previous: ProviderState?
    func load(_ provider: ProviderID) throws -> ProviderState? { previous?.provider == provider ? previous : nil }
    func save(_ state: ProviderState) throws { throw UsageFailure.unavailable }
    func remove(_ provider: ProviderID) throws {}
}

@Test func replacementRestoresTheOriginalCredentialWhenSnapshotPersistenceFails() async throws {
    let credentials = MemoryCredentials()
    let old = ProviderCredential(accessToken: "old-key")
    try credentials.save(old, for: .deepseek)
    let previous = ProviderState(provider: .deepseek, sessionID: old.sessionID, connection: .connected,
                                 snapshot: snapshot(.deepseek), failure: nil, updatedAt: repositoryTime)
    let repository = LiveAIUsageRepository(credentials: credentials, states: RejectingStateWrites(previous: previous),
        fetchers: [.deepseek: OutcomeFetcher(.success(snapshot(.deepseek)))])
    await #expect(throws: UsageFailure.unavailable) { try await repository.connect(.deepseek, apiKey: "next-key") }
    #expect(try credentials.load(.deepseek)?.sessionID == old.sessionID)
    #expect(try await repository.state(for: .deepseek).snapshot == previous.snapshot)
}

@Test func firstConnectionDoesNotLeaveAnOrphanedCredentialWhenSnapshotPersistenceFails() async throws {
    let credentials = MemoryCredentials()
    let repository = LiveAIUsageRepository(credentials: credentials, states: RejectingStateWrites(previous: nil),
        fetchers: [.deepseek: OutcomeFetcher(.success(snapshot(.deepseek)))])
    await #expect(throws: UsageFailure.unavailable) { try await repository.connect(.deepseek, apiKey: "unit-key") }
    #expect(try credentials.load(.deepseek) == nil)
    #expect(try await repository.state(for: .deepseek).connection == .disconnected)
}

private actor OutcomeFetcher: UsageFetching {
    let result: Result<UsageSnapshot, UsageFailure>
    let delay: Duration
    private var count = 0
    init(_ result: Result<UsageSnapshot, UsageFailure>, delay: Duration = .zero) {
        self.result = result
        self.delay = delay
    }
    func fetch(credential: ProviderCredential) async throws -> UsageSnapshot {
        count += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        return try result.get()
    }
    func calls() -> Int { count }
}

/// 故意忽略取消的测试网络，用于重现退出后才返回的响应。
private actor LateFetcher: UsageFetching {
    private var completion: CheckedContinuation<UsageSnapshot, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private var isStarted = false
    func fetch(credential: ProviderCredential) async throws -> UsageSnapshot {
        await withCheckedContinuation { continuation in
            completion = continuation
            isStarted = true
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if isStarted { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() { completion?.resume(returning: snapshot(.deepseek)); completion = nil }
}

@Test func concurrentRefreshesShareOneRequest() async throws {
    let credentials = MemoryCredentials()
    try credentials.save(ProviderCredential(accessToken: "unit-key"), for: .deepseek)
    let fetcher = OutcomeFetcher(.success(snapshot(.deepseek)), delay: .milliseconds(100))
    let repository = LiveAIUsageRepository(credentials: credentials, states: MemoryStates(), fetchers: [.deepseek: fetcher])
    async let first = repository.refresh(.deepseek)
    async let second = repository.refresh(.deepseek)
    let (a, b) = try await (first, second)
    #expect(a == b)
    #expect(await fetcher.calls() == 1)
}

@Test func logoutRejectsEvenANetworkResponseThatIgnoresCancellation() async throws {
    let credentials = MemoryCredentials()
    let states = MemoryStates()
    try credentials.save(ProviderCredential(accessToken: "unit-key"), for: .deepseek)
    let fetcher = LateFetcher()
    let repository = LiveAIUsageRepository(credentials: credentials, states: states, fetchers: [.deepseek: fetcher])
    let request = Task { try await repository.refresh(.deepseek) }
    await fetcher.waitUntilStarted()
    try await repository.disconnect(.deepseek)
    await fetcher.finish()
    await #expect(throws: CancellationError.self) { try await request.value }
    #expect(try credentials.load(.deepseek) == nil)
    #expect(try states.load(.deepseek) == nil)
    #expect(try await repository.state(for: .deepseek).connection == .disconnected)
}

@Test func aFailedRefreshKeepsTheOriginalDataTimeAndOtherProviders() async throws {
    let credentials = MemoryCredentials()
    let states = MemoryStates()
    let credential = ProviderCredential(accessToken: "unit-key")
    try credentials.save(credential, for: .deepseek)
    let old = snapshot(.deepseek, at: repositoryTime.addingTimeInterval(-600))
    try states.save(ProviderState(provider: .deepseek, sessionID: credential.sessionID, connection: .connected,
                                  snapshot: old, failure: nil, updatedAt: repositoryTime))
    let fetcher = OutcomeFetcher(.failure(.network))
    let repository = LiveAIUsageRepository(credentials: credentials, states: states,
                                           fetchers: [.deepseek: fetcher], clock: RepositoryClock())
    await #expect(throws: UsageFailure.network) { try await repository.refresh(.deepseek) }
    let value = try await repository.state(for: .deepseek)
    #expect(value.snapshot == old)
    #expect(value.failure == .network)
    #expect(value.isStale(at: repositoryTime))
    #expect(try await repository.state(for: .claude).connection == .disconnected)
}

@Test func rateLimitPreventsANewRequestBeforeTheServerDeadline() async throws {
    let credentials = MemoryCredentials()
    try credentials.save(ProviderCredential(accessToken: "unit-key"), for: .deepseek)
    let deadline = repositoryTime.addingTimeInterval(300)
    let fetcher = OutcomeFetcher(.failure(.rateLimited(retryAt: deadline)))
    let repository = LiveAIUsageRepository(credentials: credentials, states: MemoryStates(),
                                           fetchers: [.deepseek: fetcher], clock: RepositoryClock())
    for _ in 0..<2 {
        await #expect(throws: UsageFailure.rateLimited(retryAt: deadline)) { try await repository.refresh(.deepseek) }
    }
    #expect(await fetcher.calls() == 1)
}

private actor RotatingRenewer: UsageCredentialRenewing {
    private var count = 0
    func renew(_ credential: ProviderCredential, for provider: ProviderID) async throws -> ProviderCredential {
        count += 1
        return ProviderCredential(sessionID: credential.sessionID, accessToken: "renewed-access",
                                  refreshToken: "renewed-refresh", expiresAt: repositoryTime.addingTimeInterval(3600))
    }
    func calls() -> Int { count }
}

@Test func tokenRotationIsSavedEvenWhenTheFollowingUsageRequestFails() async throws {
    let credentials = MemoryCredentials()
    try credentials.save(ProviderCredential(accessToken: "old-access", refreshToken: "old-refresh",
                                             expiresAt: repositoryTime.addingTimeInterval(-1)), for: .codex)
    let renewer = RotatingRenewer()
    let repository = LiveAIUsageRepository(credentials: credentials, states: MemoryStates(),
                                           fetchers: [.codex: OutcomeFetcher(.failure(.network))],
                                           renewer: renewer, clock: RepositoryClock())
    await #expect(throws: UsageFailure.network) { try await repository.refresh(.codex) }
    #expect(try credentials.load(.codex)?.refreshToken == "renewed-refresh")
    #expect(await renewer.calls() == 1)
}

@Test func aRejectedReplacementDoesNotEraseTheWorkingAccount() async throws {
    let credentials = MemoryCredentials()
    let original = ProviderCredential(accessToken: "working-key")
    try credentials.save(original, for: .deepseek)
    let repository = LiveAIUsageRepository(credentials: credentials, states: MemoryStates(),
                                           fetchers: [.deepseek: OutcomeFetcher(.failure(.reconnectRequired))])
    await #expect(throws: UsageFailure.reconnectRequired) { try await repository.connect(.deepseek, apiKey: "bad-key") }
    #expect(try credentials.load(.deepseek)?.sessionID == original.sessionID)
}

@Test func widgetNeverRotatesAnExpiredCredential() async throws {
    let credentials = MemoryCredentials()
    let states = MemoryStates()
    let credential = ProviderCredential(accessToken: "expired-access", refreshToken: "unit-refresh",
                                          expiresAt: repositoryTime.addingTimeInterval(-1))
    try credentials.save(credential, for: .codex)
    let old = snapshot(.codex, at: repositoryTime.addingTimeInterval(-3600))
    try states.save(ProviderState(provider: .codex, sessionID: credential.sessionID, connection: .connected,
                                  snapshot: old, failure: nil, updatedAt: old.fetchedAt))
    let fetcher = OutcomeFetcher(.success(snapshot(.codex)))
    let reader = WidgetUsageReader(credentials: credentials, states: states,
                                    fetchers: [.codex: fetcher], clock: RepositoryClock())
    let value = await reader.state(for: .codex, refresh: true)
    #expect(value.failure == .appRefreshRequired)
    #expect(value.snapshot == old)
    #expect(await fetcher.calls() == 0)
    #expect(try credentials.load(.codex)?.refreshToken == "unit-refresh")
}

@Test func widgetDiscardsTheOldAccountIfLogoutHappensDuringItsRequest() async throws {
    let credentials = MemoryCredentials()
    let states = MemoryStates()
    try credentials.save(ProviderCredential(accessToken: "unit-key"), for: .deepseek)
    let fetcher = LateFetcher()
    let reader = WidgetUsageReader(credentials: credentials, states: states, fetchers: [.deepseek: fetcher])
    let request = Task { await reader.state(for: .deepseek, refresh: true) }
    await fetcher.waitUntilStarted()
    try credentials.remove(.deepseek)
    try states.remove(.deepseek)
    await fetcher.finish()
    let value = await request.value
    #expect(value.connection == .disconnected)
    #expect(value.snapshot == nil)
    #expect(try states.load(.deepseek) == nil)
}

@Test func widgetCanFetchWithoutWritingTheSharedSnapshot() async throws {
    let credentials = MemoryCredentials()
    let states = MemoryStates()
    let credential = ProviderCredential(accessToken: "unit-key")
    try credentials.save(credential, for: .deepseek)
    let old = snapshot(.deepseek, at: repositoryTime.addingTimeInterval(-3600))
    try states.save(ProviderState(provider: .deepseek, sessionID: credential.sessionID, connection: .connected,
                                  snapshot: old, failure: nil, updatedAt: old.fetchedAt))
    let fetcher = OutcomeFetcher(.success(snapshot(.deepseek)))
    let reader = WidgetUsageReader(credentials: credentials, states: states,
                                    fetchers: [.deepseek: fetcher], clock: RepositoryClock())
    let value = await reader.state(for: .deepseek, refresh: true)
    let second = await reader.state(for: .deepseek, refresh: true)
    #expect(value.snapshot?.fetchedAt == repositoryTime)
    #expect(second == value)
    #expect(await fetcher.calls() == 1)
    #expect(try states.load(.deepseek)?.snapshot == old)
    #expect(try credentials.load(.deepseek)?.sessionID == credential.sessionID)
}

@Test func widgetKeepsTheServerRetryDeadlineEvenWhenItsMemorySnapshotIsNewer() async throws {
    let credentials = MemoryCredentials()
    let states = MemoryStates()
    let credential = ProviderCredential(accessToken: "unit-key")
    try credentials.save(credential, for: .deepseek)
    let old = snapshot(.deepseek, at: repositoryTime.addingTimeInterval(-600))
    let fetcher = OutcomeFetcher(.success(snapshot(.deepseek)))
    let reader = WidgetUsageReader(credentials: credentials, states: states,
                                   fetchers: [.deepseek: fetcher], clock: RepositoryClock())
    _ = await reader.state(for: .deepseek, refresh: true)
    let deadline = repositoryTime.addingTimeInterval(120)
    try states.save(ProviderState(provider: .deepseek, sessionID: credential.sessionID, connection: .connected,
        snapshot: old, failure: .rateLimited(retryAt: deadline), updatedAt: repositoryTime))
    let value = await reader.state(for: .deepseek, refresh: true)
    #expect(value.snapshot?.fetchedAt == repositoryTime)
    #expect(value.failure == .rateLimited(retryAt: deadline))
    #expect(await fetcher.calls() == 1)
}

@Test func historyWriteFailureDoesNotConvertASuccessfulRefreshIntoANetworkFailure() async throws {
    let credentials = MemoryCredentials(); let states = MemoryStates()
    try credentials.save(ProviderCredential(accessToken: "fixture-key"), for: .deepseek)
    let history = HistoryLifecycleProbe(failRecord: true)
    let repository = LiveAIUsageRepository(credentials: credentials, states: states,
        fetchers: [.deepseek: OutcomeFetcher(.success(snapshot(.deepseek)))], history: history)
    #expect(try await repository.refresh(.deepseek) == snapshot(.deepseek))
    #expect(try states.load(.deepseek)?.failure == nil)
    #expect(try states.load(.deepseek)?.snapshot == snapshot(.deepseek))
}

@Test func failedSegmentChangeDoesNotAppendNewAccountToThePreviousSession() async throws {
    let credentials = MemoryCredentials()
    let history = HistoryLifecycleProbe(failSegment: true)
    let repository = LiveAIUsageRepository(credentials: credentials, states: MemoryStates(),
        fetchers: [.deepseek: OutcomeFetcher(.success(snapshot(.deepseek)))], history: history)
    try await repository.connect(.deepseek, apiKey: "fixture-key")
    #expect(try await repository.state(for: .deepseek).connection == .connected)
    #expect(await history.records.isEmpty)
}

@Test func historyRemovalFailureIsReportedAndCanBeRetriedAfterCredentialsAreGone() async throws {
    let credentials = MemoryCredentials(); let history = HistoryLifecycleProbe(failForget: true)
    try credentials.save(ProviderCredential(accessToken: "fixture-key"), for: .deepseek)
    let repository = LiveAIUsageRepository(credentials: credentials, states: MemoryStates(),
        fetchers: [:], history: history)
    await #expect(throws: UsageFailure.unavailable) { try await repository.disconnect(.deepseek) }
    #expect(try credentials.load(.deepseek) == nil)
    await history.allowRemoval()
    try await repository.disconnect(.deepseek)
    #expect(await history.forgotten == [.provider(.deepseek)])
}

@Test func disconnectDuringHistorySegmentationCannotAppendTheOldAccountAfterRemoval() async throws {
    let history = HistoryLifecycleProbe(pause: .segment)
    let repository = LiveAIUsageRepository(credentials: MemoryCredentials(), states: MemoryStates(),
        fetchers: [.deepseek: OutcomeFetcher(.success(snapshot(.deepseek)))], history: history)
    let connection = Task { try await repository.connect(.deepseek, apiKey: "fixture-key") }
    await history.waitUntilPaused()
    try await repository.disconnect(.deepseek)
    await history.release()
    await #expect(throws: CancellationError.self) { try await connection.value }
    #expect(await history.records.isEmpty)
    #expect(try await repository.state(for: .deepseek).connection == .disconnected)
}

@Test func disconnectDuringHistoryWriteCannotReturnAStaleSuccessfulRefresh() async throws {
    let credentials = MemoryCredentials(); let history = HistoryLifecycleProbe(pause: .record)
    try credentials.save(ProviderCredential(accessToken: "fixture-key"), for: .deepseek)
    let repository = LiveAIUsageRepository(credentials: credentials, states: MemoryStates(),
        fetchers: [.deepseek: OutcomeFetcher(.success(snapshot(.deepseek)))], history: history)
    let refresh = Task { try await repository.refresh(.deepseek) }
    await history.waitUntilPaused()
    try await repository.disconnect(.deepseek)
    await history.release()
    await #expect(throws: CancellationError.self) { try await refresh.value }
    #expect(try await repository.state(for: .deepseek).connection == .disconnected)
}
