import AIUsageDomain
import Foundation

/// 首页总览：熊的情绪与一句人话摘要，只依赖各平台展示结果。
public struct DashboardOverviewPresentation: Equatable, Sendable {
    public enum Mood: String, Sendable { case calm, watchful, urgent, asleep }
    public struct Tightest: Equatable, Sendable {
        public let provider: ProviderID
        public let window: UsageWindowPresentation
    }
    public let providers: [ProviderDashboardPresentation]
    public let tightest: Tightest?
    public let mood: Mood

    public init(providers: [ProviderDashboardPresentation]) {
        self.providers = providers
        let candidates = providers.compactMap { value -> Tightest? in
            guard value.state?.connection == .connected, let window = value.summaryWindow else { return nil }
            return Tightest(provider: value.provider, window: window)
        }
        let tightest = candidates.enumerated().min {
            $0.element.window.remaining == $1.element.window.remaining
                ? $0.offset < $1.offset : $0.element.window.remaining < $1.element.window.remaining
        }?.element
        self.tightest = tightest
        let connected = providers.contains { $0.state?.connection == .connected }
        let balanceBlocked = providers.contains { $0.state?.connection == .connected && $0.state?.snapshot?.isAvailable == false }
        let lowest = tightest?.window.remaining ?? 100
        if !connected { mood = .asleep }
        else if lowest <= 5 || balanceBlocked { mood = .urgent }
        else if lowest <= 20 { mood = .watchful }
        else { mood = .calm }
    }

    /// 例：「Codex 5 小时 还剩 42%，19:30 重置」。
    public func summary(at date: Date) -> String {
        guard let tightest else {
            return mood == .asleep ? "还没连接账户，轻松熊先睡会儿。" : "暂时没有可比较的额度窗口。"
        }
        let head = ProviderPresentation.name(tightest.provider) + " " + tightest.window.shortLabel
            + " 还剩 " + ProviderPresentation.percent(tightest.window.remaining)
        guard let reset = tightest.window.window.resetsAt, reset > date else { return head }
        let sameDay = Calendar.current.isDate(reset, inSameDayAs: date)
        return head + "，" + reset.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened) + " 重置"
    }

    public var moodLabel: String {
        switch mood { case .calm: "额度充足"; case .watchful: "留意用量"; case .urgent: "额度告急"; case .asleep: "未连接" }
    }
}
