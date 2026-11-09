import AIUsageDomain
import Foundation
import Observation

@MainActor @Observable
public final class RelayModel {
    public private(set) var states: [RelayState] = []
    public private(set) var refreshing: Set<UUID> = []
    public private(set) var saving = false
    public private(set) var clearing = false
    public private(set) var feedback: [UUID: String] = [:]
    public var message: String?
    private let repository: any RelayRepository
    private let onDataChange: @MainActor @Sendable () -> Void
    private var revision: UInt64 = 0
    @ObservationIgnored private var published: [ReloadSignature]?
    private struct ReloadSignature: Equatable {
        let account: RelayAccount; let balances: [CurrencyBalance]?; let available: Bool?; let failure: UsageFailure?
        init(_ state: RelayState) {
            account = state.account; balances = state.snapshot?.balances; available = state.snapshot?.isAvailable; failure = state.failure
        }
    }
    public init(repository: any RelayRepository, onDataChange: @escaping @MainActor @Sendable () -> Void = {}) {
        self.repository = repository; self.onDataChange = onDataChange
    }
    public func load() async {
        let expected = revision
        do {
            let values = try await repository.states()
            if expected == revision { states = values; if published == nil { published = values.map(ReloadSignature.init) } }
        }
        catch { message = "读取中转缓存失败，原数据未清除。" }
    }
    public func refreshIfNeeded() async {
        await load()
        let ids = states.filter { $0.snapshot.map { Date().timeIntervalSince($0.fetchedAt) >= 300 } ?? true }.map(\.id)
        await withTaskGroup(of: Void.self) { group in
            for id in ids { group.addTask { _ = await self.refresh(id, report: false) } }
        }
    }
    @discardableResult public func refresh(_ id: UUID, report: Bool = true) async -> Bool {
        guard !clearing, !saving, !refreshing.contains(id), let old = states.first(where: { $0.id == id }) else { return false }
        let expected = revision
        refreshing.insert(id); feedback[id] = nil
        defer { refreshing.remove(id) }
        var success = false
        do { _ = try await repository.refresh(id); success = true }
        catch is CancellationError { return false }
        catch { if report && expected == revision { message = AIUsageModel.explanation(error) } }
        guard expected == revision else { return false }
        await load()
        let next = states.first { $0.id == id }
        feedback[id] = success ? (old.snapshot?.balances == next?.snapshot?.balances && old.snapshot?.isAvailable == next?.snapshot?.isAvailable ? "已核实，余额未变化" : "余额已更新") : "读取未完成，已保留上次读数"
        publish()
        return success
    }
    @discardableResult public func save(id: UUID?, name: String, endpoint: RelayEndpoint, key: String) async -> Bool {
        guard !saving, !clearing else { return false }
        saving = true; revision &+= 1
        message = nil
        defer { saving = false }
        do {
            try await repository.save(id: id, name: name, endpoint: endpoint, key: key)
            await load(); publish(); return true
        } catch is CancellationError { return false }
        catch { message = AIUsageModel.explanation(error); return false }
    }
    @discardableResult public func delete(_ id: UUID) async -> Bool {
        guard !clearing, !saving else { return false }
        revision &+= 1
        do { try await repository.delete(id); await load(); feedback[id] = nil; publish(); return true }
        catch { message = "删除未完成，请重试以清除本机密钥与缓存。"; return false }
    }
    public func clearLocalData() async -> Bool {
        guard !clearing, !saving else { return false }
        clearing = true; revision &+= 1
        defer { clearing = false }
        do { try await repository.clear(); states = []; feedback = [:]; message = nil; publish(); return true }
        catch { message = "中转数据尚未完全清除，请重试。"; return false }
    }
    private func publish() {
        let current = states.map(ReloadSignature.init)
        if current != published { published = current; onDataChange() }
    }
}
