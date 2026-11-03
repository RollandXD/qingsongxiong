import AIUsageDomain
import BearFoundation
import Foundation

/// Widget 的受限取数路径：可以使用未过期 token，只读凭据，绝不轮换或写入共享快照。
public actor WidgetUsageReader {
    private let credentials: any UsageCredentialStore
    private let states: any UsageStateStore
    private let fetchers: [ProviderID: any UsageFetching]
    private let clock: any BearClock
    private var memory: [ProviderID: ProviderState] = [:]
    private var requests: [ProviderID: Task<ProviderState, Never>] = [:]

    public init(credentials: any UsageCredentialStore, states: any UsageStateStore,
                fetchers: [ProviderID: any UsageFetching], clock: any BearClock = SystemBearClock()) {
        self.credentials = credentials
        self.states = states
        self.fetchers = fetchers
        self.clock = clock
    }

    public func state(for provider: ProviderID, refresh: Bool) async -> ProviderState {
        do {
            guard let credential = try credentials.load(provider) else {
                memory[provider] = nil
                return .disconnected(provider, at: clock.now())
            }
            let disk = try states.load(provider)
            let stored = disk?.sessionID == credential.sessionID ? disk : nil
            if let stored, stored.connection == .reconnectRequired { return stored }
            let cached = latest(memory[provider], stored, sessionID: credential.sessionID)
            if !refresh { return cached ?? empty(provider, credential: credential) }
            if let cached, let snapshot = cached.snapshot, clock.now().timeIntervalSince(snapshot.fetchedAt) < 300 {
                return cached
            }
            if let cached, case .rateLimited(let date) = cached.failure, let date, date > clock.now() { return cached }
            if let expiration = credential.expiresAt, expiration <= clock.now() {
                return result(provider, credential: credential, snapshot: cached?.snapshot, failure: .appRefreshRequired)
            }
            guard let fetcher = fetchers[provider] else { return cached ?? empty(provider, credential: credential) }
            if let request = requests[provider] { return await request.value }
            let request = Task { await self.fetch(provider, credential: credential, cached: cached, fetcher: fetcher) }
            requests[provider] = request
            let value = await request.value
            requests[provider] = nil
            return value
        } catch {
            return ProviderState(provider: provider, sessionID: nil, connection: .unknown,
                                 snapshot: nil, failure: .unavailable, updatedAt: clock.now())
        }
    }

    private func fetch(_ provider: ProviderID, credential: ProviderCredential, cached: ProviderState?,
                       fetcher: any UsageFetching) async -> ProviderState {
        let value: ProviderState
        do {
            let snapshot = try await fetcher.fetch(credential: credential)
            guard snapshot.provider == provider else { throw UsageFailure.invalidResponse }
            value = result(provider, credential: credential, snapshot: snapshot, failure: nil)
        } catch {
            var failure = (error as? UsageFailure) ?? .network
            if failure == .reconnectRequired && credential.refreshToken != nil { failure = .appRefreshRequired }
            value = result(provider, credential: credential, snapshot: cached?.snapshot, failure: failure)
        }
        // 退出或更换账户后，迟到的组件请求不能重新展示旧账户数据。
        guard let current = try? credentials.load(provider), current.sessionID == credential.sessionID else {
            memory[provider] = nil
            return .disconnected(provider, at: clock.now())
        }
        memory[provider] = value
        return value
    }

    private func latest(_ a: ProviderState?, _ b: ProviderState?, sessionID: UUID) -> ProviderState? {
        let values = [a, b].compactMap { $0 }.filter { $0.sessionID == sessionID }
        return values.max {
            let aDate = $0.snapshot?.fetchedAt ?? .distantPast
            let bDate = $1.snapshot?.fetchedAt ?? .distantPast
            return aDate == bDate ? $0.updatedAt < $1.updatedAt : aDate < bDate
        }
    }
    private func empty(_ provider: ProviderID, credential: ProviderCredential) -> ProviderState {
        result(provider, credential: credential, snapshot: nil, failure: nil)
    }
    private func result(_ provider: ProviderID, credential: ProviderCredential,
                        snapshot: UsageSnapshot?, failure: UsageFailure?) -> ProviderState {
        ProviderState(provider: provider, sessionID: credential.sessionID,
                      connection: failure == .reconnectRequired ? .reconnectRequired : .connected,
                      snapshot: snapshot, failure: failure, updatedAt: clock.now())
    }
}
