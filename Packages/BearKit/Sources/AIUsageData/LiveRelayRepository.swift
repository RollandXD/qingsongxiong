import AIUsageDomain
import BearFoundation
import Foundation

public actor LiveRelayRepository: RelayRepository {
    private let store: any RelayRecordStoring
    private let credentials: any RelayCredentialStoring
    private let adapter: RelayBalanceAdapter
    private let clock: any BearClock
    private var generations: [UUID: UInt64] = [:]
    private var epoch: UInt64 = 0
    private struct Request { let id: UUID; let task: Task<RelaySnapshot, any Error> }
    private var requests: [UUID: Request] = [:]
    public init(store: any RelayRecordStoring, credentials: any RelayCredentialStoring,
                adapter: RelayBalanceAdapter, clock: any BearClock = SystemBearClock()) {
        self.store = store; self.credentials = credentials; self.adapter = adapter; self.clock = clock
    }
    public func states() async throws -> [RelayState] { try records() }
    private func records() throws -> [RelayState] { try store.load()?.states ?? [] }
    private func persist(_ values: [RelayState], retiring: [RelayAccount] = [], activating: RelayAccount? = nil) throws {
        let retired = ((try store.load()?.retiredAccounts ?? []) + retiring).filter { $0 != activating }
        try store.save(RelayRecord(states: values, retiredAccounts: retired, updatedAt: clock.now()))
    }
    /// 旧槽清理是可恢复的；清理失败的槽仍有目录引用，不遗失在 Keychain 中。
    private func cleanupRetired() throws {
        guard let record = try store.load() else { return }
        var retained: [RelayAccount] = []
        for account in record.retiredAccounts ?? [] {
            do { try credentials.remove(account) } catch { retained.append(account) }
        }
        try store.save(RelayRecord(states: record.states, retiredAccounts: retained, updatedAt: clock.now()))
    }
    private func invalidate(_ id: UUID) -> UInt64 {
        generations[id, default: 0] &+= 1
        requests.removeValue(forKey: id)?.task.cancel()
        return generations[id, default: 0]
    }
    private func ensure(_ id: UUID, generation: UInt64) throws {
        try Task.checkCancellation()
        guard generations[id, default: 0] == generation else { throw CancellationError() }
    }
    public func save(id: UUID?, name: String, endpoint: RelayEndpoint, key: String) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw UsageFailure.invalidResponse }
        let previous = try records().first { $0.id == id }
        if id != nil && previous == nil { throw UsageFailure.disconnected }
        let account = RelayAccount(id: previous?.id ?? UUID(), displayName: name, endpoint: endpoint)
        let key = try RelayBalanceAdapter.validatedKey(key.isEmpty ? (previous.flatMap { try? credentials.load($0.account) } ?? "") : key)
        let generation = invalidate(account.id)
        let epoch = self.epoch
        let snapshot = try await adapter.fetch(endpoint: endpoint, key: key)
        try ensure(account.id, generation: generation)
        guard epoch == self.epoch else { throw CancellationError() }
        var values = try records()
        guard id == nil || values.contains(where: { $0.account == previous?.account }) else { throw CancellationError() }
        guard values.count < 12 || previous != nil else { throw UsageFailure.unavailable }
        // 先落恢复目录，再写新凭据：提交与回滚同时失败、甚至进程中断，也不会留下无目录的密钥。
        try persist(values, retiring: [account])
        let state = RelayState(account: account, snapshot: snapshot, updatedAt: clock.now())
        do {
            try credentials.save(key, for: account)
            if let index = values.firstIndex(where: { $0.id == account.id }) { values[index] = state } else { values.append(state) }
            try persist(values, retiring: previous.map { [$0.account] } ?? [], activating: account)
        } catch {
            try? cleanupRetired() // 清理失败保留恢复目录；旧账户不变，clear() 可再次处理。
            throw UsageFailure.unavailable
        }
        try? cleanupRetired() // 提交已成功；清理失败由持久化退役列表承接，clear() 强制重试。
    }
    public func refresh(_ id: UUID) async throws -> RelaySnapshot {
        try Task.checkCancellation()
        if let request = requests[id] {
            return try await withTaskCancellationHandler { try await request.task.value } onCancel: { request.task.cancel() }
        }
        guard let state = try records().first(where: { $0.id == id }),
              let key = try credentials.load(state.account) else { throw UsageFailure.disconnected }
        if state.failure == .reconnectRequired { throw UsageFailure.reconnectRequired }
        if case .rateLimited(let retryAt) = state.failure, let retryAt, retryAt > clock.now() { throw UsageFailure.rateLimited(retryAt: retryAt) }
        let generation = generations[id, default: 0]
        let token = UUID()
        let task = Task { try await self.performRefresh(state, key: key, generation: generation) }
        requests[id] = Request(id: token, task: task)
        defer { if requests[id]?.id == token { requests[id] = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    private func performRefresh(_ state: RelayState, key: String, generation: UInt64) async throws -> RelaySnapshot {
        do {
            let snapshot = try await adapter.fetch(endpoint: state.account.endpoint, key: key)
            try ensure(state.id, generation: generation)
            try update(state.account, snapshot: snapshot, failure: nil)
            return snapshot
        } catch {
            try ensure(state.id, generation: generation)
            if error is CancellationError { throw CancellationError() }
            var failure = (error as? UsageFailure) ?? .network
            if case .rateLimited(nil) = failure { failure = .rateLimited(retryAt: clock.now().addingTimeInterval(300)) }
            try update(state.account, snapshot: state.snapshot, failure: failure)
            throw failure
        }
    }
    private func update(_ account: RelayAccount, snapshot: RelaySnapshot?, failure: UsageFailure?) throws {
        var values = try records()
        guard let index = values.firstIndex(where: { $0.account == account }) else { throw CancellationError() }
        values[index] = RelayState(account: account, snapshot: snapshot, failure: failure, updatedAt: clock.now())
        try persist(values)
    }
    public func delete(_ id: UUID) async throws {
        _ = invalidate(id)
        var values = try records()
        guard let state = values.first(where: { $0.id == id }) else { return }
        // 先删密钥；若目录写失败，下一次删除仍能清理，组件也不能再取数。
        try credentials.remove(state.account)
        values.removeAll { $0.id == id }
        try persist(values)
        try? cleanupRetired()
    }
    public func clear() async throws {
        epoch &+= 1
        let record = try store.load()
        for state in record?.states ?? [] { _ = invalidate(state.id) }
        for account in (record?.states.map(\.account) ?? []) + (record?.retiredAccounts ?? []) {
            try credentials.remove(account)
        }
        try store.save(RelayRecord(states: [], updatedAt: clock.now()))
    }
}
