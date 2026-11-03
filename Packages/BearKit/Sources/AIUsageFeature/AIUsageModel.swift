import AIUsageDomain
import Foundation
import Observation

@MainActor @Observable
public final class AIUsageModel {
    public private(set) var states: [ProviderID: ProviderState] = [:]
    public private(set) var refreshing: Set<ProviderID> = []
    public private(set) var connecting: Set<ProviderID> = []
    public var message: String?
    public private(set) var dataRevision = 0
    private let repository: any AIUsageRepository
    private let connector: (any AIUsageAccountConnecting)?
    private let onDataChange: @MainActor @Sendable () -> Void
    private var revisions: [ProviderID: UInt64] = [:]

    public init(repository: any AIUsageRepository, connector: (any AIUsageAccountConnecting)?,
                onDataChange: @escaping @MainActor @Sendable () -> Void = {}) {
        self.repository = repository
        self.connector = connector
        self.onDataChange = onDataChange
    }

    public func canConnect(_ provider: ProviderID) -> Bool { connector?.supports(provider) == true }

    public func loadCached() async {
        for provider in ProviderID.allCases { await reload(provider, revision: revisions[provider, default: 0]) }
    }

    public func refreshIfNeeded() async {
        let due = ProviderID.allCases.filter { provider in
            guard let state = states[provider], state.connection == .connected else { return false }
            return state.snapshot.map { Date().timeIntervalSince($0.fetchedAt) >= 300 } ?? true
        }
        await withTaskGroup(of: Void.self) { group in
            for provider in due { group.addTask { await self.refresh(provider, reportFailure: false) } }
        }
    }

    public func refresh(_ provider: ProviderID, reportFailure: Bool = true) async {
        guard !refreshing.contains(provider), !connecting.contains(provider) else { return }
        let revision = revisions[provider, default: 0]
        refreshing.insert(provider)
        defer { if revisions[provider, default: 0] == revision { refreshing.remove(provider) } }
        do { _ = try await repository.refresh(provider) }
        catch is CancellationError { return }
        catch { if reportFailure && revisions[provider, default: 0] == revision { message = Self.explanation(error) } }
        await reload(provider, revision: revision)
        if revisions[provider, default: 0] == revision { publishChange() }
    }

    @discardableResult
    public func connect(_ provider: ProviderID, key: String?) async -> Bool {
        guard let connector, connector.supports(provider), !connecting.contains(provider) else { return false }
        revisions[provider, default: 0] &+= 1
        let revision = revisions[provider, default: 0]
        refreshing.remove(provider)
        connecting.insert(provider)
        message = nil
        defer { if revisions[provider, default: 0] == revision { connecting.remove(provider) } }
        do {
            try await connector.connect(provider, apiKey: key)
            guard revisions[provider, default: 0] == revision else { return false }
            await reload(provider, revision: revision)
            publishChange()
            return true
        } catch is CancellationError { return false }
        catch {
            if revisions[provider, default: 0] == revision { message = Self.explanation(error) }
            return false
        }
    }

    public func disconnect(_ provider: ProviderID) async {
        revisions[provider, default: 0] &+= 1
        refreshing.remove(provider)
        connecting.remove(provider)
        await connector?.cancel(provider)
        do {
            try await repository.disconnect(provider)
            states[provider] = .disconnected(provider, at: Date())
            publishChange()
        } catch { message = "退出未完成，请重试以清除本机数据。" }
    }

    private func reload(_ provider: ProviderID, revision: UInt64) async {
        do {
            let state = try await repository.state(for: provider)
            guard revisions[provider, default: 0] == revision else { return }
            states[provider] = state
        } catch { message = "读取本机缓存失败，已有数据未被清除。" }
    }

    private func publishChange() { dataRevision &+= 1; onDataChange() }

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
