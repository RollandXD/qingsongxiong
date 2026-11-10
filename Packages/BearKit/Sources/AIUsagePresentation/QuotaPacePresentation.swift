import AIUsageDomain
import Foundation

/// 均匀配速参考线的一个锚点：按参考线走，此刻剩余应为 `remainingPercent`。
public struct QuotaPaceAnchor: Equatable, Sendable {
    public let date: Date
    public let remainingPercent: Double

    public init(date: Date, remainingPercent: Double) {
        self.date = date
        self.remainingPercent = remainingPercent
    }
}

/// 当前窗口的“均匀配速参考”，不是真实消耗速度的预测。
///
/// 定义：已知可信周期 `D` 与未来重置时刻 `R` 时，此刻参考剩余为
/// `100 × clamp((R - now) / D, 0...1)`。周期过半时参考剩余 50%；
/// 实际还剩 70%，就比参考多剩 20 个百分点。这是位置比较，
/// 不是“必须花完”的指标，也不是按真实速度外推的耗尽时间。
public struct QuotaPace: Equatable, Sendable {
    public let windowID: String
    public let label: String
    public let periodSeconds: Int
    public let basis: QuotaPeriodBasis
    /// 名义周期起点 = `resetsAt - periodSeconds`；是推算值，不冒充服务端给的精确开始时间。
    public let periodStart: Date
    public let resetsAt: Date
    public let referenceRemainingPercent: Double
    public let actualRemainingPercent: Double

    public init(windowID: String, label: String, periodSeconds: Int, basis: QuotaPeriodBasis,
                periodStart: Date, resetsAt: Date,
                referenceRemainingPercent: Double, actualRemainingPercent: Double) {
        self.windowID = windowID
        self.label = label
        self.periodSeconds = periodSeconds
        self.basis = basis
        self.periodStart = periodStart
        self.resetsAt = resetsAt
        self.referenceRemainingPercent = referenceRemainingPercent
        self.actualRemainingPercent = actualRemainingPercent
    }

    /// 实际减参考，单位是“百分点”，不是“百分之几”。
    public var deltaPercentagePoints: Double { actualRemainingPercent - referenceRemainingPercent }

    public var isOnOrAhead: Bool { deltaPercentagePoints >= 0 }

    /// 图表参考线的两个端点：周期起点 100% → 重置时刻 0%。
    public var referenceAnchors: [QuotaPaceAnchor] {
        [QuotaPaceAnchor(date: periodStart, remainingPercent: 100),
         QuotaPaceAnchor(date: resetsAt, remainingPercent: 0)]
    }

    /// “比参考多剩 20 个百分点”这类描述；差值取绝对值，方向用文字说清。
    public var comparison: String {
        let magnitude = abs(deltaPercentagePoints)
        if magnitude < 0.05 { return "刚好在参考线上" }
        let text = magnitude.formatted(.number.precision(.fractionLength(0...1))) + " 个百分点"
        return deltaPercentagePoints > 0 ? "比参考多剩 " + text : "比参考少剩 " + text
    }

    /// 说明周期依据，避免把名义推导讲成服务端精确起点。
    public var basisNote: String {
        let hours = Double(periodSeconds) / 3_600
        let length = hours >= 24 && hours.truncatingRemainder(dividingBy: 24) == 0
            ? String(Int(hours / 24)) + " 天"
            : hours.formatted(.number.precision(.fractionLength(0...1))) + " 小时"
        switch basis {
        case .serverReported: return "按服务端窗口时长 " + length + " 推算"
        case .knownWindowRule: return "按已核实的 " + length + " 窗口规则推算"
        }
    }
}

/// 不给判断时要说清原因，不能让界面看起来像“已回满”或“数据正常”。
public enum QuotaPaceUnavailableReason: Equatable, Sendable {
    case notConnected
    case noReading
    case staleReading
    case failedReading
    case unknownPeriod
    case resetPassed

    public var text: String {
        switch self {
        case .notConnected: "还没连上账户，无法给出配速参考"
        case .noReading: "还没有额度读数"
        case .staleReading: "读数已过期，先刷新再给配速参考"
        case .failedReading: "刷新未完成，保留上次实测值，暂不判断配速"
        case .unknownPeriod: "服务端没给窗口时长，不推算配速"
        case .resetPassed: "重置时间已过，等待刷新确认后重新计算"
        }
    }
}

public enum QuotaPaceStatus: Equatable, Sendable {
    case available(QuotaPace)
    case unavailable(QuotaPaceUnavailableReason)

    public var pace: QuotaPace? {
        if case .available(let pace) = self { return pace }
        return nil
    }
}

public enum QuotaPaceCalculator {
    /// 纯计算：只看窗口自身的可信周期与重置时刻，不判断新鲜度。
    public static func pace(for window: QuotaWindow, now: Date) -> QuotaPace? {
        guard let seconds = window.periodSeconds, seconds > 0, let reset = window.resetsAt else { return nil }
        let period = TimeInterval(seconds)
        let remaining = reset.timeIntervalSince(now)
        // 已过重置时刻（等刷新确认）或重置时间超出整个周期：都不按“回满”处理。
        guard remaining > 0, remaining <= period else { return nil }
        let reference = 100 * (remaining / period)
        let actual = min(100, window.remainingPercent)
        return QuotaPace(windowID: window.id, label: window.label, periodSeconds: seconds,
                         basis: window.periodBasis ?? .serverReported,
                         periodStart: reset.addingTimeInterval(-period), resetsAt: reset,
                         referenceRemainingPercent: reference, actualRemainingPercent: actual)
    }

    /// 带状态判断的入口：过期、失败、断连都退化为“不判断”并给出中文原因。
    public static func status(for window: UsageWindowPresentation,
                              state: ProviderState?,
                              isStale: Bool,
                              now: Date) -> QuotaPaceStatus {
        guard let state else { return .unavailable(.noReading) }
        guard state.connection == .connected else { return .unavailable(.notConnected) }
        if state.failure != nil { return .unavailable(.failedReading) }
        guard state.snapshot != nil else { return .unavailable(.noReading) }
        if isStale { return .unavailable(.staleReading) }
        guard let pace = pace(for: window.window, now: now) else {
            return .unavailable(window.window.periodSeconds == nil ? .unknownPeriod : .resetPassed)
        }
        return .available(pace)
    }
}

/// 一份“当前窗口 + 周窗口”的配速摘要，首页与详情共用。
public struct QuotaPaceBoard: Equatable, Sendable {
    public let dashboard: ProviderDashboardPresentation
    public let now: Date
    public let currentWindow: UsageWindowPresentation?
    public let weeklyWindow: UsageWindowPresentation?

    public init(dashboard: ProviderDashboardPresentation, now: Date) {
        let jar = HoneyJarPresentation(dashboard)
        self.dashboard = dashboard
        self.now = now
        currentWindow = jar.fiveHour
        weeklyWindow = jar.weekly
    }

    public func status(for window: UsageWindowPresentation) -> QuotaPaceStatus {
        QuotaPaceCalculator.status(for: window, state: dashboard.state,
                                   isStale: dashboard.isStale, now: now)
    }

    public var current: QuotaPaceStatus? { currentWindow.map(status(for:)) }
    public var weekly: QuotaPaceStatus? { weeklyWindow.map(status(for:)) }

    /// 任一窗口能给出参考线时用它；都不行返回最先遇到的原因，供界面解释。
    public var primaryUnavailableReason: QuotaPaceUnavailableReason? {
        let statuses = [current, weekly].compactMap { $0 }
        // 连窗口都没有（没连上/没读数）时不能说“周期未知”，那是另一种误导。
        guard !statuses.isEmpty else { return .noReading }
        for status in statuses {
            if case .unavailable(let reason) = status { return reason }
        }
        return nil
    }
}
