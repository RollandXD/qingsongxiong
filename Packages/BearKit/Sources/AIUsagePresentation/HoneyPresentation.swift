import AIUsageDomain
import Foundation

/// 额度紧张程度的统一阈值（百分比，与 `QuotaWindow.remainingPercent` 同单位）。
public enum QuotaLevel: Sendable, Equatable { case normal, watch, urgent }

public enum QuotaThresholds {
    public static let watch: Double = 20.0
    public static let urgent: Double = 5.0
    public static func level(remainingPercent: Double) -> QuotaLevel {
        if remainingPercent <= urgent { return .urgent }
        if remainingPercent <= watch { return .watch }
        return .normal
    }
}

/// 首页「每家一只双格蜜罐」：左格 5 小时窗口，右格本周窗口，其余窗口进详情页「附加限额」。
public struct HoneyJarPresentation: Equatable, Sendable {
    public let dashboard: ProviderDashboardPresentation
    public let fiveHour: UsageWindowPresentation?
    public let weekly: UsageWindowPresentation?
    /// 除 fiveHour / weekly 之外的所有窗口，保持原顺序。
    public let extras: [UsageWindowPresentation]
    public var provider: ProviderID { dashboard.provider }
    public var isConnected: Bool { dashboard.state?.connection == .connected }

    private enum Slot { case fiveHour, weekly }

    /// 识别依据：
    /// - Claude：`UsageResponseParser.claude` 的字段名，id 精确匹配 `five_hour` / `seven_day`。
    /// - Codex：id 为 `rate_limit.primary_window` / `rate_limit.secondary_window`，不含时长；
    ///   解析器用 `limit_window_seconds` 生成 label（18000 秒为「5 小时」，604800 秒为「7 天」），按 label 判断。
    /// - 仍无法判定的 role == .general 窗口，按 resetsAt 先后兜底：早的算 fiveHour，晚的算 weekly；
    ///   没有重置时间的排在有重置时间的之后，彼此保持原顺序。
    private static func slot(of window: UsageWindowPresentation, provider: ProviderID) -> Slot? {
        switch provider {
        case .claude:
            switch window.id {
            case "five_hour": return .fiveHour
            case "seven_day": return .weekly
            default: return nil
            }
        case .codex:
            guard window.id.hasPrefix("rate_limit.") else { return nil }
            switch window.label {
            case "5 小时": return .fiveHour
            case "7 天": return .weekly
            default: return nil
            }
        case .deepseek: return nil
        }
    }

    public init(_ dashboard: ProviderDashboardPresentation) {
        self.dashboard = dashboard
        let general = dashboard.windows.filter { $0.role == .general }
        var five: UsageWindowPresentation?
        var week: UsageWindowPresentation?
        var unresolved: [UsageWindowPresentation] = []
        for window in general {
            switch Self.slot(of: window, provider: dashboard.provider) {
            case .fiveHour? where five == nil: five = window
            case .weekly? where week == nil: week = window
            default: unresolved.append(window)
            }
        }
        let ordered = unresolved.enumerated().sorted { lhs, rhs in
            switch (lhs.element.window.resetsAt, rhs.element.window.resetsAt) {
            case let (a?, b?): return a == b ? lhs.offset < rhs.offset : a < b
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
        if five == nil, week == nil {
            five = ordered.first
            if ordered.count >= 2 { week = ordered.last }
        } else if five == nil {
            five = ordered.first
        } else if week == nil {
            week = ordered.last
        }
        fiveHour = five
        weekly = week
        let used = Set([five?.id, week?.id].compactMap { $0 })
        extras = dashboard.windows.filter { !used.contains($0.id) }
    }
}

public enum ResetCountdown {
    /// 「2天23时」「3时12分」「8分」；最少「1分」，负数按 0 处理。
    public static func compact(_ interval: TimeInterval) -> String {
        let clamped = interval.isFinite ? min(max(0, interval), 3_153_600_000) : 0
        let seconds = Int(clamped)
        let days = seconds / 86_400
        let hours = seconds % 86_400 / 3_600
        let minutes = seconds % 3_600 / 60
        if days >= 1 { return "\(days)天\(hours)时" }
        if seconds >= 3_600 { return "\(hours)时\(minutes)分" }
        return "\(max(1, minutes))分"
    }

    /// 「今天 20:00」「明天 03:58」「周四 17:55」，24 小时制，不依赖系统 locale。
    public static func moment(_ reset: Date, now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: reset)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let clock = (hour < 10 ? "0" : "") + String(hour) + ":" + (minute < 10 ? "0" : "") + String(minute)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: reset)).day ?? 0
        if days == 0 { return "今天 " + clock }
        if days == 1 { return "明天 " + clock }
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = calendar.component(.weekday, from: reset)
        let name = names.indices.contains(weekday - 1) ? names[weekday - 1] : ""
        return name + " " + clock
    }
}

/// 时间尺预览：假设之后不再使用，重置时间一到窗口即回满。
public enum ScrubForecast {
    public static func remainingPercent(_ window: UsageWindowPresentation, now: Date, offset: TimeInterval) -> Double {
        if let reset = window.window.resetsAt, reset <= now.addingTimeInterval(offset) { return 100 }
        return window.remaining
    }

    /// 各窗口重置时刻相对 now 的偏移，仅保留 (0, horizon]，升序去重。
    public static func resetOffsets(_ windows: [UsageWindowPresentation], now: Date,
                                    horizon: TimeInterval = 7 * 86_400) -> [TimeInterval] {
        let values = windows.compactMap { $0.window.resetsAt?.timeIntervalSince(now) }
            .filter { $0 > 0 && $0 <= horizon }
            .sorted()
        var result: [TimeInterval] = []
        for value in values where result.last != value { result.append(value) }
        return result
    }
}

/// 首页顶部一句话：所有已连接平台的 5 小时 / 周窗口里最紧的一个。
public struct HeroPresentation: Equatable, Sendable {
    public let lead: String
    public let tail: String
    public let isWarning: Bool
    public let subtitle: String

    public init(overview: DashboardOverviewPresentation, jars: [HoneyJarPresentation],
                now: Date, calendar: Calendar = .current) {
        struct Candidate {
            let provider: ProviderID
            let name: String
            let window: UsageWindowPresentation
        }
        var candidates: [Candidate] = []
        for jar in jars where jar.isConnected {
            if let window = jar.fiveHour {
                candidates.append(Candidate(provider: jar.provider,
                                            name: ProviderPresentation.name(jar.provider) + " 5 小时", window: window))
            }
            if let window = jar.weekly {
                candidates.append(Candidate(provider: jar.provider,
                                            name: ProviderPresentation.name(jar.provider) + " 周额度", window: window))
            }
        }
        let tightest = candidates.enumerated().min { lhs, rhs in
            let a = lhs.element.window, b = rhs.element.window
            if a.remaining != b.remaining { return a.remaining < b.remaining }
            switch (a.window.resetsAt, b.window.resetsAt) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return lhs.offset < rhs.offset
            }
        }?.element

        guard let tightest else {
            let asleep = overview.mood == .asleep || !jars.contains { $0.isConnected }
            lead = asleep ? "还没连上账户" : "暂时没有额度读数"
            tail = ""
            isWarning = false
            subtitle = asleep ? "轻松熊先睡会儿" : "等下次刷新再看"
            return
        }
        let remaining = tightest.window.remaining
        guard QuotaThresholds.level(remainingPercent: remaining) != .normal else {
            lead = "额度都够用"
            tail = ""
            isWarning = false
            subtitle = "最低是 " + tightest.name + " " + ProviderPresentation.percent(remaining)
            return
        }
        lead = tightest.name
        tail = remaining == 0 ? "用完了" : "只剩 " + ProviderPresentation.percent(remaining)
        isWarning = true
        if let reset = tightest.window.window.resetsAt {
            if reset > now {
                subtitle = ResetCountdown.moment(reset, now: now, calendar: calendar)
                    + " 回满，还要 " + ResetCountdown.compact(reset.timeIntervalSince(now))
            } else {
                subtitle = "重置时间已过，等待刷新确认"
            }
        } else {
            subtitle = "未提供重置时间"
        }
    }
}
