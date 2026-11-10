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

/// 设备本地、有界、可清除的额度/余额时间线。
///
/// 只记成功提交之后的观测，不上传、不写凭据；读取失败时自愈成空归档，
/// 而不是让首页因为一份坏文件打不开。
public actor UsageHistoryService: UsageHistoryRecording {
    private let store: AtomicRecordStore<UsageHistoryArchive>
    private let clock: any BearClock
    private let byteBudget: Int
    private var cached: UsageHistoryArchive?

    public init(container: URL, clock: any BearClock = SystemBearClock(),
                byteBudget: Int = UsageHistoryArchive.maximumBytes) throws {
        store = try AtomicRecordStore(container: container, namespace: "ai-usage-history")
        self.clock = clock
        self.byteBudget = byteBudget
    }

    public func archive() async throws -> UsageHistoryArchive {
        try currentArchive()
    }

    public func record(snapshot: UsageSnapshot, for ref: AccountRef) async throws {
        // 用快照自己的抓取时间，而不是“现在”：迟到写回也能落在正确位置。
        let entries = snapshot.windows.map { window in
            HistoryEntry(metric: .quota(windowID: window.id), value: .percent(window.remainingPercent))
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
            // 什么都没了就把文件一起删掉，不留下空壳。
            try? store.remove()
            cached = archive
            return
        }
        try commit(archive)
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
            if try store.write(archive) { cached = archive }
            else { cached = try store.read() }
        } catch { throw UsageHistoryFailure.unavailable }
    }

    /// 读取失败（坏文件、权限、解码错误）时自愈为空归档并重写，绝不让界面打不开。
    private func currentArchive() throws -> UsageHistoryArchive {
        if let cached { return cached }
        var rebuilt = false
        let loaded: UsageHistoryArchive
        do {
            loaded = try store.read() ?? .empty(at: clock.now())
        } catch {
            // write 会先读旧记录做时间戳比较，坏文件不先删就永远写不进去。
            try? store.remove()
            loaded = .empty(at: clock.now())
            rebuilt = true
        }
        // 打开时先按保留期清一次，避免读进来的老数据继续占用预算。
        let pruned = UsageHistoryReducer.pruned(loaded, now: clock.now(), byteBudget: byteBudget)
        if rebuilt || pruned != loaded { _ = try? store.write(pruned) }
        cached = pruned
        return pruned
    }
}
