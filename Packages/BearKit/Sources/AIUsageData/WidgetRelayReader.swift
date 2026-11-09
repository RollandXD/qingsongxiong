import AIUsageDomain
import BearFoundation
import Foundation

/// 只读目录/凭据，不轮换 Key、不写共享文件；交互取数保留在本进程与返回时间线。
public actor WidgetRelayReader {
    private let store: any RelayRecordReading
    private let credentials: any RelayCredentialReading
    private let adapter: RelayBalanceAdapter
    private let clock: any BearClock
    private var memory: [UUID: RelayState] = [:]
    private var requests: [UUID: Task<RelayState?, Never>] = [:]
    public init(store: any RelayRecordReading, credentials: any RelayCredentialReading,
                adapter: RelayBalanceAdapter, clock: any BearClock = SystemBearClock()) {
        self.store = store; self.credentials = credentials; self.adapter = adapter; self.clock = clock
    }
    public func cachedStates() -> [RelayState] { (try? store.load()?.states) ?? [] }
    public func state(_ id: UUID, refresh: Bool, force: Bool = false) async -> RelayState? {
        guard let disk = try? store.load()?.states.first(where: { $0.id == id }),
              let key = try? credentials.load(disk.account) else { memory[id] = nil; return nil }
        let remembered = memory[id].flatMap { $0.account.sessionID == disk.account.sessionID ? $0 : nil }
        let cached = remembered.flatMap { value -> RelayState? in
            let localDate = value.snapshot?.fetchedAt ?? .distantPast
            let diskDate = disk.snapshot?.fetchedAt ?? .distantPast
            return localDate > diskDate || (localDate == diskDate && value.updatedAt >= disk.updatedAt) ? value : nil
        } ?? disk
        guard refresh else { return cached }
        if disk.failure == .reconnectRequired { return disk }
        let retryAt = ([disk, cached] + (remembered.map { [$0] } ?? [])).compactMap { state -> Date? in
            guard case .rateLimited(let date) = state.failure, let date, date > clock.now() else { return nil }; return date
        }.max()
        if let retryAt { return RelayState(account: disk.account, snapshot: cached.snapshot, failure: .rateLimited(retryAt: retryAt), updatedAt: clock.now()) }
        if !force, let snapshot = cached.snapshot, clock.now().timeIntervalSince(snapshot.fetchedAt) < 300 { return cached }
        if let task = requests[id] { return await task.value }
        let task = Task { await self.fetch(cached, key: key) }
        requests[id] = task
        defer { requests[id] = nil }
        return await task.value
    }
    private func fetch(_ cached: RelayState, key: String) async -> RelayState? {
        let value: RelayState
        do {
            let snapshot = try await adapter.fetch(endpoint: cached.account.endpoint, key: key)
            value = RelayState(account: cached.account, snapshot: snapshot, updatedAt: clock.now())
        } catch {
            var failure = (error as? UsageFailure) ?? .network
            if case .rateLimited(nil) = failure { failure = .rateLimited(retryAt: clock.now().addingTimeInterval(300)) }
            value = RelayState(account: cached.account, snapshot: cached.snapshot, failure: failure, updatedAt: clock.now())
        }
        guard let account = try? store.load()?.states.first(where: { $0.id == cached.id })?.account,
              account.sessionID == cached.account.sessionID, (try? credentials.load(account)) != nil else {
            memory[cached.id] = nil; return nil
        }
        memory[cached.id] = value
        return value
    }
}
