import AIUsageData
import AIUsageDomain
import AIUsagePresentation
import Foundation
import Observation

@MainActor @Observable
public final class AIUsageModel {
    public private(set) var states: [ProviderID: ProviderState] = [:]
    public private(set) var refreshing: Set<ProviderID> = []
    public private(set) var connecting: Set<ProviderID> = []
    public private(set) var clearing = false
    public private(set) var refreshFeedback: [ProviderID: String] = [:]
    public private(set) var animatedRefresh: Set<ProviderID> = []
    public private(set) var verifiedRefresh: Set<ProviderID> = []
    public var message: String?
    public private(set) var dataRevision = 0
    /// 首页两张主卡的选择；加载完成前用默认顺序，避免首帧空白。
    public private(set) var dashboard = DashboardPreferences.initial(at: Date())
    /// 设备本地历史（过去用量时间线的数据源）；不进快照、不上传。
    public private(set) var history = UsageHistoryArchive.empty(at: Date())
    public private(set) var historyLoaded = false
    private let repository: any AIUsageRepository
    private let connector: (any AIUsageAccountConnecting)?
    private let preferences: any DashboardPreferencesStoring
    private let historyReader: (any UsageHistoryReading)?
    private let onDataChange: @MainActor @Sendable () -> Void
    private var revisions: [ProviderID: UInt64] = [:]

    public init(repository: any AIUsageRepository, connector: (any AIUsageAccountConnecting)?,
                preferences: any DashboardPreferencesStoring = MemoryDashboardPreferencesStore(),
                historyReader: (any UsageHistoryReading)? = nil,
                onDataChange: @escaping @MainActor @Sendable () -> Void = {}) {
        self.repository = repository
        self.connector = connector
        self.preferences = preferences
        self.historyReader = historyReader
        self.onDataChange = onDataChange
    }

    /// 读一次本地历史。文件不存在或坏了就当没有历史，不能让首页因此打不开。
    public func loadHistory() async {
        guard let historyReader else { return }
        let loaded = try? await historyReader.archive()
        historyLoaded = true
        guard let loaded else { return }
        history = loaded
    }

    /// 读取用户选择；坏文件或旧版本只回退到默认，不让首页打不开。
    public func loadDashboard() {
        guard let stored = try? preferences.load() else { return }
        guard let stored else { return }
        dashboard = stored
    }

    /// 把某个位置换成指定账户/中转（已在另一位置则互换，绝不重复）。
    public func setCard(_ ref: AccountRef?, atSlot slot: Int) {
        let next = dashboard.setting(ref, atSlot: slot, at: Date())
        guard next != dashboard else { return }
        // 先改界面再落盘：写失败也不该让点击看起来没反应。
        dashboard = next
        try? preferences.save(next)
        publishChange()
    }

    public func swapCards() {
        let next = dashboard.swapping(0, 1, at: Date())
        guard next != dashboard else { return }
        dashboard = next
        try? preferences.save(next)
        publishChange()
    }

    /// 中转被删除后清掉指向它的空位；其他位置保持不动。
    /// 只清理 `keeping` 里不存在的 id，所以调用方必须先确认中转列表已加载，否则会把用户的选择误清。
    public func pruneRelayCards(keeping ids: Set<UUID>) {
        let stale = Set(dashboard.cards.compactMap(\.relayID)).subtracting(ids)
        guard !stale.isEmpty else { return }
        var next = dashboard
        for id in stale { next = next.removingRelay(id, at: Date()) }
        guard next != dashboard else { return }
        dashboard = next
        try? preferences.save(next)
    }

    public func canConnect(_ provider: ProviderID) -> Bool { connector?.supports(provider) == true }

    public func loadCached() async {
        for provider in ProviderID.allCases { await reload(provider, revision: revisions[provider, default: 0]) }
        reloadPolicy.seedIfNeeded(states, at: Date())
    }

    public func refreshIfNeeded() async {
        guard !Task.isCancelled, !clearing else { return }
        // 后台任务可能冷启动 App；不能依赖首页先加载过内存状态。
        await loadCached()
        guard !Task.isCancelled, !clearing else { return }
        let due = ProviderID.allCases.filter { provider in
            guard let state = states[provider], state.connection == .connected else { return false }
            return state.snapshot.map { Date().timeIntervalSince($0.fetchedAt) >= 300 } ?? true
        }
        await withTaskGroup(of: Void.self) { group in
            for provider in due { group.addTask { await self.refresh(provider, reportFailure: false, animated: false) } }
        }
    }

    public func refresh(_ provider: ProviderID, reportFailure: Bool = true, animated: Bool = true) async {
        guard !clearing, !refreshing.contains(provider), !connecting.contains(provider) else { return }
        if animated { animatedRefresh.insert(provider) } else { animatedRefresh.remove(provider) }
        refreshFeedback[provider] = nil
        verifiedRefresh.remove(provider)
        let previous = states[provider]?.snapshot
        var succeeded = false
        let revision = revisions[provider, default: 0]
        refreshing.insert(provider)
        defer { if revisions[provider, default: 0] == revision { refreshing.remove(provider) } }
        do { _ = try await repository.refresh(provider); succeeded = true }
        catch is CancellationError { return }
        catch { if reportFailure && revisions[provider, default: 0] == revision { message = Self.explanation(error) } }
        let reloaded = await reload(provider, revision: revision)
        if revisions[provider, default: 0] == revision {
            let verified = succeeded && reloaded
            if verified { verifiedRefresh.insert(provider) }
            if animated {
                let next = states[provider]?.snapshot
                let changed = previous?.windows != next?.windows || previous?.balances != next?.balances || previous?.isAvailable != next?.isAvailable
                refreshFeedback[provider] = verified ? (changed ? "已更新读数" : "已核实，读数未变化") : "读取未完成，已保留原状态"
            }
            publishChange()
        }
    }

    @discardableResult
    public func connect(_ provider: ProviderID, key: String?) async -> Bool {
        guard !clearing, let connector, connector.supports(provider), !connecting.contains(provider) else { return false }
        revisions[provider, default: 0] &+= 1
        let revision = revisions[provider, default: 0]
        refreshing.remove(provider)
        refreshFeedback[provider] = nil
        animatedRefresh.remove(provider)
        verifiedRefresh.remove(provider)
        connecting.insert(provider)
        message = nil
        defer { if revisions[provider, default: 0] == revision { connecting.remove(provider) } }
        do {
            try await connector.connect(provider, apiKey: key)
            guard revisions[provider, default: 0] == revision else { return false }
            await reload(provider, revision: revision)
            publishChange(force: true)
            return true
        } catch is CancellationError { return false }
        catch {
            if revisions[provider, default: 0] == revision { message = Self.explanation(error) }
            return false
        }
    }

    @discardableResult
    public func disconnect(_ provider: ProviderID) async -> Bool {
        revisions[provider, default: 0] &+= 1
        refreshing.remove(provider)
        refreshFeedback[provider] = nil
        animatedRefresh.remove(provider)
        verifiedRefresh.remove(provider)
        connecting.remove(provider)
        await connector?.cancel(provider)
        do {
            try await repository.disconnect(provider)
            states[provider] = .disconnected(provider, at: Date())
            if !clearing { publishChange(force: true) }
            return true
        } catch { message = "退出未完成，请重试以清除本机数据。"; return false }
    }

    /// 功能模块拥有自己的清除流程，App 壳只调用注册的操作。
    public func clearLocalData() async -> Bool {
        guard !clearing else { return false }
        clearing = true
        defer { clearing = false }
        var succeeded = true
        for provider in ProviderID.allCases {
            if !(await disconnect(provider)) { succeeded = false }
        }
        publishChange(force: true)
        if succeeded { message = nil }
        return succeeded
    }

    @discardableResult
    private func reload(_ provider: ProviderID, revision: UInt64) async -> Bool {
        do {
            let state = try await repository.state(for: provider)
            guard revisions[provider, default: 0] == revision else { return false }
            states[provider] = state
            return true
        } catch { message = "读取本机缓存失败，已有数据未被清除。"; return false }
    }

    @ObservationIgnored private var reloadPolicy = WidgetReloadPolicy()
    /// 页面修订号每次都递增；小组件仅在读数、账户或失败状态改变时通知。
    private func publishChange(force: Bool = false) {
        dataRevision &+= 1
        if reloadPolicy.shouldReload(states, at: Date(), force: force) { onDataChange() }
    }

    public static func explanation(_ error: any Error) -> String {
        guard let failure = error as? UsageFailure else { return "操作暂未完成，请稍后重试。" }
        switch failure {
        case .disconnected: return "请先连接这个平台的账户。"
        case .reconnectRequired: return "账户授权已失效，请重新连接。"
        case .invalidCredential: return "密钥格式无效，请在手机上重新输入。"
        case .invalidResponse: return "服务返回了无法识别的数据，已保留上次读数。"
        case .network: return "网络请求未完成，请检查当前网络。"
        case .appRefreshRequired: return "请打开 App 更新授权。"
        case .authorizationTimedOut: return "授权等待已结束，请重新连接。"
        case .authorizationRejected: return "平台未接受当前授权请求，请更新轻松熊后重试。"
        case .serviceHTTP(let status): return "平台请求未完成（HTTP \(status)），请检查当前网络与账户权限。"
        case .rateLimited(let date):
            return date.map { "请求过于频繁，请在 \($0.formatted(date: .omitted, time: .shortened)) 后刷新。" }
                ?? "请求过于频繁，请稍后刷新。"
        case .unavailable: return "服务暂时不可用，请稍后重试。"
        case .deviceVerificationRequired: return "请先完成安装与共享能力检查。"
        }
    }
}
