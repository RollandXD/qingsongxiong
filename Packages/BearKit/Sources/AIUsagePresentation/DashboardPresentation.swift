import AIUsageDomain
import Foundation

public enum UsageWindowRole: String, Sendable {
    case general, model, codeReview, other
    public var label: String {
        switch self { case .general: "通用额度"; case .model: "模型专属"; case .codeReview: "代码审查"; case .other: "独立限制" }
    }
}

public struct UsageWindowPresentation: Identifiable, Equatable, Sendable {
    public let window: QuotaWindow
    public let role: UsageWindowRole
    public var id: String { window.id }
    public var remaining: Double { window.remainingPercent }
    public var fraction: Double { min(1, max(0, remaining / 100)) }
    public var label: String { window.label }
    public func resetLabel(at date: Date) -> String {
        guard let reset = window.resetsAt else { return "未提供重置时间" }
        guard reset > date else { return "重置时间已过，等待刷新确认" }
        return reset.formatted(date: .abbreviated, time: .shortened) + " 重置"
    }
    public var shortLabel: String {
        if id == "seven_day_opus" { return "Opus" }
        if id == "seven_day_sonnet" { return "Sonnet" }
        if role == .codeReview { return "审查" }
        return window.label.components(separatedBy: " · ").first ?? window.label
    }
    public init(_ window: QuotaWindow, provider: ProviderID) {
        self.window = window
        switch provider {
        case .codex:
            if window.id.hasPrefix("rate_limit.") { role = .general }
            else if window.id.hasPrefix("code_review_rate_limit.") { role = .codeReview }
            else { role = .other }
        case .claude:
            if ["five_hour", "seven_day"].contains(window.id) { role = .general }
            else if window.id.hasPrefix("seven_day_") { role = .model }
            else { role = .other }
        case .deepseek: role = .other
        }
    }
}

public struct BalancePartPresentation: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let amount: Decimal
    public let fraction: Double
}

public struct BalancePresentation: Identifiable, Equatable, Sendable {
    public var id: String { balance.currency }
    public let balance: CurrencyBalance
    public var parts: [BalancePartPresentation]? {
        guard balance.total > 0, let grant = balance.granted, let topUp = balance.toppedUp,
              grant >= 0, topUp >= 0, grant + topUp == balance.total else { return nil }
        let fraction = NSDecimalNumber(decimal: grant / balance.total).doubleValue
        guard fraction.isFinite, (0...1).contains(fraction) else { return nil }
        return [
            BalancePartPresentation(id: "grant", label: "赠送余额", amount: grant, fraction: fraction),
            BalancePartPresentation(id: "top-up", label: "充值余额", amount: topUp, fraction: 1 - fraction),
        ]
    }
    public init(_ balance: CurrencyBalance) { self.balance = balance }
}

public struct ProviderDashboardPresentation: Equatable, Sendable {
    public let provider: ProviderID
    public let state: ProviderState?
    public let windows: [UsageWindowPresentation]
    public let balances: [BalancePresentation]
    public let isStale: Bool
    public var generalWindows: [UsageWindowPresentation] { windows.filter { $0.role == .general } }
    public var summaryWindow: UsageWindowPresentation? {
        let candidates = generalWindows.isEmpty ? windows : generalWindows
        return candidates.enumerated().min {
            $0.element.remaining == $1.element.remaining ? $0.offset < $1.offset : $0.element.remaining < $1.element.remaining
        }?.element
    }
    public var compactWindows: [UsageWindowPresentation] {
        Array((generalWindows.isEmpty ? windows : generalWindows).prefix(2))
    }
    public var status: String {
        guard let state else { return "读取本机状态" }
        if state.connection == .disconnected { return "尚未连接" }
        if state.connection == .unknown { return "暂不可读取" }
        if state.connection == .reconnectRequired { return "需要重新连接" }
        if state.failure == .appRefreshRequired { return "打开 App 更新授权" }
        if state.snapshot == nil { return state.failure == nil ? "等待首次读取" : "读取未完成" }
        if isStale { return "旧读数" }
        if state.snapshot?.isAvailable == false { return "当前不可调用" }
        if let window = summaryWindow {
            if window.remaining == 0 { return "窗口已用尽" }
            if window.remaining <= 20 { return "余量偏低" }
        }
        return "已同步"
    }
    public var headline: String {
        if let balance = balances.first { return ProviderPresentation.money(balance.balance.total, currency: balance.balance.currency) }
        if let window = summaryWindow { return "剩余 " + ProviderPresentation.percent(window.remaining) }
        return "—"
    }
    public init(provider: ProviderID, state: ProviderState?, at date: Date) {
        self.provider = provider
        self.state = state
        windows = (state?.snapshot?.windows ?? []).map { UsageWindowPresentation($0, provider: provider) }
        balances = (state?.snapshot?.balances ?? []).map(BalancePresentation.init)
        isStale = state?.isStale(at: date) ?? true
    }
}
