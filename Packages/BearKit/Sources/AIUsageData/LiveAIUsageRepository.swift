import AIUsageDomain
import BearFoundation
import Foundation

public protocol UsageFetching: Sendable {
    func fetch(credential: ProviderCredential) async throws -> UsageSnapshot
}

public protocol UsageCredentialRenewing: Sendable {
    func renew(_ credential: ProviderCredential, for provider: ProviderID) async throws -> ProviderCredential
}

public struct ReconnectionRequiredRenewer: UsageCredentialRenewing {
    public init() {}
    public func renew(_ credential: ProviderCredential, for provider: ProviderID) async throws -> ProviderCredential {
        throw UsageFailure.reconnectRequired
    }
}

extension DeepSeekAdapter: UsageFetching {
    public func fetch(credential: ProviderCredential) async throws -> UsageSnapshot {
        try await fetch(apiKey: credential.accessToken)
    }
}

/// 主 App 的唯一写入者与令牌续期者。Widget 使用独立的受限读取接口。
public actor LiveAIUsageRepository: AIUsageRepository, AIUsageAccountConnecting {
    private let credentials: any UsageCredentialStore
    private let states: any UsageStateStore
    private let fetchers: [ProviderID: any UsageFetching]
    private let renewer: any UsageCredentialRenewing
    private let clock: any BearClock
    private var generations: [ProviderID: UInt64] = [:]
    private struct InFlight {
        let id: UUID
        let task: Task<UsageSnapshot, any Error>
    }
    private var requests: [ProviderID: InFlight] = [:]

    public init(credentials: any UsageCredentialStore, states: any UsageStateStore,
                fetchers: [ProviderID: any UsageFetching],
                renewer: any UsageCredentialRenewing = ReconnectionRequiredRenewer(),
                clock: any BearClock = SystemBearClock()) {
        self.credentials = credentials
        self.states = states
        self.fetchers = fetchers
        self.renewer = renewer
        self.clock = clock
    }

    public func state(for provider: ProviderID) async throws -> ProviderState {
        try currentState(for: provider)
    }

    private func currentState(for provider: ProviderID) throws -> ProviderState {
        guard let credential = try credentials.load(provider) else { return .disconnected(provider, at: clock.now()) }
        if let state = try states.load(provider), state.sessionID == credential.sessionID { return state }
        return ProviderState(provider: provider, sessionID: credential.sessionID, connection: .connected,
                             snapshot: nil, failure: nil, updatedAt: clock.now())
    }

    public func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot? {
        try currentState(for: provider).snapshot
    }

    public func connect(_ provider: ProviderID, apiKey: String?) async throws {
        guard provider == .deepseek, let apiKey else { throw UsageFailure.invalidCredential }
        try await replaceCredential(ProviderCredential(accessToken: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)), for: provider)
    }

    public nonisolated func supports(_ provider: ProviderID) -> Bool { provider == .deepseek }
    public func cancel(_ provider: ProviderID) async { _ = invalidate(provider) }

    /// 先验证新账户，失败时原账户仍保留；提交前再次检查退出/替换代次。
    public func replaceCredential(_ credential: ProviderCredential, for provider: ProviderID) async throws {
        try Task.checkCancellation()
        guard let fetcher = fetchers[provider] else { throw UsageFailure.unavailable }
        let generation = invalidate(provider)
        let snapshot = try await fetcher.fetch(credential: credential)
        try ensureCurrent(provider, generation)
        guard snapshot.provider == provider else { throw UsageFailure.invalidResponse }
        try credentials.save(credential, for: provider)
        try states.save(ProviderState(provider: provider, sessionID: credential.sessionID, connection: .connected,
                                      snapshot: snapshot, failure: nil, updatedAt: clock.now()))
    }

    public func refresh(_ provider: ProviderID) async throws -> UsageSnapshot {
        if let request = requests[provider] { return try await request.task.value }
        guard let credential = try credentials.load(provider) else { throw UsageFailure.disconnected }
        let previous = try currentState(for: provider)
        guard previous.connection != .reconnectRequired else { throw UsageFailure.reconnectRequired }
        if case .rateLimited(let retryAt) = previous.failure, let retryAt, retryAt > clock.now() {
            throw UsageFailure.rateLimited(retryAt: retryAt)
        }
        let generation = generations[provider, default: 0]
        let id = UUID()
        let task = Task { try await self.performRefresh(provider, credential: credential, generation: generation) }
        requests[provider] = InFlight(id: id, task: task)
        defer { if requests[provider]?.id == id { requests[provider] = nil } }
        return try await task.value
    }

    private func performRefresh(_ provider: ProviderID, credential initial: ProviderCredential,
                                generation: UInt64) async throws -> UsageSnapshot {
        do {
            guard let fetcher = fetchers[provider] else { throw UsageFailure.unavailable }
            var credential = initial
            var didRenew = false
            if let expiration = credential.expiresAt, expiration <= clock.now().addingTimeInterval(60) {
                credential = try await renew(credential, provider: provider, generation: generation)
                didRenew = true
            }
            let snapshot: UsageSnapshot
            do { snapshot = try await fetcher.fetch(credential: credential) }
            catch UsageFailure.reconnectRequired where !didRenew && credential.refreshToken != nil {
                credential = try await renew(credential, provider: provider, generation: generation)
                snapshot = try await fetcher.fetch(credential: credential)
            }
            try ensureCurrent(provider, generation)
            guard snapshot.provider == provider else { throw UsageFailure.invalidResponse }
            try states.save(ProviderState(provider: provider, sessionID: credential.sessionID, connection: .connected,
                                          snapshot: snapshot, failure: nil, updatedAt: clock.now()))
            return snapshot
        } catch {
            try ensureCurrent(provider, generation)
            if error is CancellationError { throw CancellationError() }
            let failure = (error as? UsageFailure) ?? .network
            let previous = try? states.load(provider)
            let snapshot = previous?.sessionID == initial.sessionID ? previous?.snapshot : nil
            let connection: AccountConnection = failure == .reconnectRequired ? .reconnectRequired : .connected
            try states.save(ProviderState(provider: provider, sessionID: initial.sessionID, connection: connection,
                                          snapshot: snapshot, failure: failure, updatedAt: clock.now()))
            throw failure
        }
    }

    private func renew(_ credential: ProviderCredential, provider: ProviderID,
                       generation: UInt64) async throws -> ProviderCredential {
        guard credential.refreshToken != nil else { throw UsageFailure.reconnectRequired }
        let renewed = try await renewer.renew(credential, for: provider)
        try ensureCurrent(provider, generation)
        guard renewed.sessionID == credential.sessionID else { throw UsageFailure.invalidResponse }
        // 轮换结果先保存，后续额度请求即使失败也不会丢失新 refresh token。
        try credentials.save(renewed, for: provider)
        return renewed
    }

    public func disconnect(_ provider: ProviderID) async throws {
        _ = invalidate(provider)
        var failure: (any Error)?
        do { try credentials.remove(provider) } catch { failure = error }
        do { try states.remove(provider) } catch { if failure == nil { failure = error } }
        if failure != nil { throw UsageFailure.unavailable }
    }

    private func invalidate(_ provider: ProviderID) -> UInt64 {
        generations[provider, default: 0] &+= 1
        requests.removeValue(forKey: provider)?.task.cancel()
        return generations[provider, default: 0]
    }

    private func ensureCurrent(_ provider: ProviderID, _ generation: UInt64) throws {
        try Task.checkCancellation()
        guard generations[provider, default: 0] == generation else { throw CancellationError() }
    }
}
