import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation

/// 历史写入失败的原因，仅用于日志与测试；调用方不应因为历史写不进去而让刷新失败。
public enum UsageHistoryFailure: Error, Equatable {
    case corruptArchive
    case unavailable
}

/// 仓储只依赖这个协议，默认实现是空操作，测试与预览不需要临时目录。
public protocol UsageHistoryRecording: UsageHistoryReading {
    /// 一次成功的额度刷新：把各窗口的剩余百分比记成同一时刻的观测。
    func record(snapshot: UsageSnapshot, for ref: AccountRef) async throws
    /// 一次成功的中转余额刷新：按币种记录金额。
    func record(balances: [CurrencyBalance], at date: Date, for ref: AccountRef) async throws
    /// 账户/密钥/接口切换：只递增分段号，让曲线断开而不是假装连续。
    func beginSegment(for ref: AccountRef) async throws
    /// 隐私清除：删掉某个账户的全部本地历史。
    func forget(_ ref: AccountRef) async throws
    /// 显式清除全部本地历史；损坏或未知格式也可由用户明确删除。
    func forgetAll() async throws
}

public extension UsageHistoryRecording {
    func forgetAll() async throws {
        for source in try await archive().sources { try await forget(source.source) }
    }
}

/// 没有注入历史服务时（Widget、预览、旧测试）保持完全无副作用。
public struct DisabledUsageHistory: UsageHistoryRecording {
    public init() {}
    public func record(snapshot: UsageSnapshot, for ref: AccountRef) async throws {}
    public func record(balances: [CurrencyBalance], at date: Date, for ref: AccountRef) async throws {}
    public func beginSegment(for ref: AccountRef) async throws {}
    public func forget(_ ref: AccountRef) async throws {}
    public func archive() async throws -> UsageHistoryArchive {
        .empty(at: Date(timeIntervalSince1970: 0))
    }
}

/// 初始化失败必须可见，不能伪装成用户没有历史。
public struct UnavailableUsageHistory: UsageHistoryRecording {
    public init() {}
    public func record(snapshot: UsageSnapshot, for ref: AccountRef) async throws { throw UsageHistoryFailure.unavailable }
    public func record(balances: [CurrencyBalance], at date: Date, for ref: AccountRef) async throws { throw UsageHistoryFailure.unavailable }
    public func beginSegment(for ref: AccountRef) async throws { throw UsageHistoryFailure.unavailable }
    public func forget(_ ref: AccountRef) async throws { throw UsageHistoryFailure.unavailable }
    public func forgetAll() async throws { throw UsageHistoryFailure.unavailable }
    public func archive() async throws -> UsageHistoryArchive { throw UsageHistoryFailure.unavailable }
}

/// 设备本地、有界、可清除的额度/余额时间线。
///
/// 只记成功提交之后的观测，不上传、不写凭据；坏文件/未知版本保留并报错，
/// 界面单独提示历史不可用，不影响当前额度或余额刷新。
public actor UsageHistoryService: UsageHistoryRecording {
    private let store: AtomicRecordStore<UsageHistoryArchive>
    private let clock: any BearClock
    private let byteBudget: Int
    private var cached: UsageHistoryArchive?
    private var pendingFailure: UsageHistoryFailure?
    private var pendingArchive: UsageHistoryArchive?

    public init(container: URL, clock: any BearClock = SystemBearClock(),
                byteBudget: Int = UsageHistoryArchive.maximumBytes) throws {
        store = try AtomicRecordStore(container: container, namespace: "ai-usage-history")
        self.clock = clock
        self.byteBudget = byteBudget
    }

    public func archive() async throws -> UsageHistoryArchive {
        if let pendingArchive { try commit(pendingArchive) }
        if let pendingFailure { throw pendingFailure }
        return try currentArchive()
    }

    public func record(snapshot: UsageSnapshot, for ref: AccountRef) async throws {
        // 用快照自己的抓取时间，而不是“现在”：迟到写回也能落在正确位置。
        let entries = snapshot.windows.map { window in
            HistoryEntry(metric: .quota(windowID: window.id), value: .percent(window.remainingPercent),
                         resetsAt: window.resetsAt)
        } + snapshot.balances.map { balance in
            HistoryEntry(metric: .balance(currency: balance.currency), value: .amount(balance.total))
        }
        try record(entries: entries, at: snapshot.fetchedAt, for: ref)
    }

    public func record(balances: [CurrencyBalance], at date: Date, for ref: AccountRef) async throws {
        let entries = balances.map { balance in
            HistoryEntry(metric: .balance(currency: balance.currency), value: .amount(balance.total))
        }
        try record(entries: entries, at: date, for: ref)
    }

    public func beginSegment(for ref: AccountRef) async throws {
        let now = clock.now()
        var archive = try currentArchive()
        archive = UsageHistoryReducer.beginningSegment(for: ref, in: archive, now: now)
        try commit(archive)
    }

    public func forget(_ ref: AccountRef) async throws {
        let now = clock.now()
        var archive = try currentArchive()
        archive = UsageHistoryReducer.forgetting(ref, in: archive, now: now)
        if archive.sources.isEmpty {
            do { try store.remove() }
            catch { pendingFailure = .unavailable; throw UsageHistoryFailure.unavailable }
            cached = archive
            pendingFailure = nil
            pendingArchive = nil
            return
        }
        try commit(archive)
    }

    public func forgetAll() async throws {
        // 只有用户明确清除才允许删未知/坏文件；失败保留缓存和失败状态供重试。
        do { try store.remove() }
        catch { pendingFailure = .unavailable; throw UsageHistoryFailure.unavailable }
        cached = .empty(at: clock.now())
        pendingFailure = nil
        pendingArchive = nil
    }

    private func record(entries: [HistoryEntry], at date: Date, for ref: AccountRef) throws {
        guard !entries.isEmpty else { return }
        let now = clock.now()
        var archive = try currentArchive()
        let observation = UsageObservation(at: date, segment: archive.source(ref)?.segment ?? 0, entries: entries)
        let result = UsageHistoryReducer.recording(observation, for: ref, in: archive, now: now)
        guard result.outcome.didChange else { return }
        archive = result.archive
        try commit(UsageHistoryReducer.pruned(archive, now: now, byteBudget: byteBudget))
    }

    private func commit(_ archive: UsageHistoryArchive) throws {
        do {
            let archive = try bounded(archive)
            if try store.write(archive) { cached = archive }
            else { cached = try store.read() }
            pendingFailure = nil
            pendingArchive = nil
        } catch {
            pendingArchive = archive
            pendingFailure = .unavailable
            throw UsageHistoryFailure.unavailable
        }
    }

    /// 归约器的粗估仅用于快速预裁剪；最终按真实 JSON 字节数守预算，含信封余量。
    private func bounded(_ archive: UsageHistoryArchive) throws -> UsageHistoryArchive {
        var result = archive
        var estimateBudget = byteBudget
        while try JSONEncoder().encode(result).count + 64 > byteBudget, !result.sources.isEmpty {
            estimateBudget = max(0, estimateBudget * 3 / 4)
            result = UsageHistoryReducer.pruned(archive, now: clock.now(), byteBudget: estimateBudget)
        }
        return result
    }

    /// 缺文件才是首次使用；坏文件、未知信封/记录版本和权限错误不能吞掉或覆写。
    private func currentArchive() throws -> UsageHistoryArchive {
        if let pendingArchive { return pendingArchive }
        if let cached { return cached }
        let loaded: UsageHistoryArchive
        do { loaded = try store.read() ?? .empty(at: clock.now()) }
        catch { throw UsageHistoryFailure.corruptArchive }
        guard loaded.revision == UsageHistoryArchive.schemaRevision else {
            throw UsageHistoryFailure.corruptArchive
        }
        let pruned = try bounded(UsageHistoryReducer.pruned(loaded, now: clock.now(), byteBudget: byteBudget))
        if pruned != loaded { try commit(pruned) }
        else { cached = loaded }
        return pruned
    }
}
