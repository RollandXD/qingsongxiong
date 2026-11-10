import AIUsageDomain
import Foundation

/// 时间线上的一段连续读数。分段号变化（换账户/换密钥）就断开，不把两段连成一条假曲线。
public struct TimelineBand: Equatable, Sendable, Identifiable {
    public let segment: Int
    public let points: [TimelinePoint]
    public var id: Int { segment }

    public init(segment: Int, points: [TimelinePoint]) {
        self.segment = segment
        self.points = points
    }
}

public struct TimelinePoint: Equatable, Sendable, Identifiable {
    public let at: Date
    /// 百分比（0–100）或金额；两者不混在同一张图里，由指标决定。
    public let value: Double
    public var id: Date { at }

    public init(at: Date, value: Double) {
        self.at = at
        self.value = value
    }
}

/// 为什么这里没有曲线。空图必须说清原因，不能让人以为“用量一直是 0”。
public enum TimelineEmptyReason: Equatable, Sendable {
    /// 这个账户还没有任何历史（新版刚装、刚连接）。
    case noHistory
    /// 有历史，但选中的跨度里没有点。
    case noPointsInRange
    /// 历史太短，这个跨度还看不出来。
    case rangeTooShort
    /// 选中的指标在这个账户下没有数据。
    case metricUnavailable

    public var text: String {
        switch self {
        case .noHistory: "还没有本地历史，刷新几次后这里会出现走势。"
        case .noPointsInRange: "这个跨度里没有读数，换个跨度或稍后再看。"
        case .rangeTooShort: "历史还不够长，先看更短的跨度。"
        case .metricUnavailable: "这个账户没有该项历史。"
        }
    }
}

/// 过去用量的折线数据：按跨度过滤、按分段断线，并给出纵轴范围。
public struct UsageTimelinePresentation: Equatable, Sendable {
    public let metricLabel: String
    public let range: UsageHistoryRange
    public let bands: [TimelineBand]
    public let yRange: ClosedRange<Double>?
    public let emptyReason: TimelineEmptyReason?
    /// 断段或时间间隔过大时的说明；正常情况为 nil。
    public let gapNote: String?
    public let isBalance: Bool
    public let unitLabel: String

    public var pointCount: Int { bands.reduce(0) { $0 + $1.points.count } }
    public var isEmpty: Bool { pointCount == 0 }

    /// 相邻两点间隔超过这个倍数（相对跨度）就认为中间断过读数，不再画成直接连线。
    static let gapFactor: Double = 3

    public init(archive: UsageHistoryArchive, ref: AccountRef, metric: UsageHistoryMetric,
                range: UsageHistoryRange, now: Date, metricLabel: String) {
        self.metricLabel = metricLabel
        self.range = range
        self.isBalance = metric.isBalance
        self.unitLabel = metric.isBalance ? Self.currency(of: metric) : "%"

        let all = archive.series(for: ref, metric: metric)
        guard !all.isEmpty else {
            bands = []; yRange = nil; emptyReason = .noHistory; gapNote = nil
            return
        }
        let historyAge = now.timeIntervalSince(all.first?.at ?? now)
        let inRange = archive.series(for: ref, metric: metric, in: range, now: now)
        guard !inRange.isEmpty else {
            bands = []; yRange = nil
            emptyReason = range.isMeaningful(historyAge: historyAge) ? .noPointsInRange : .rangeTooShort
            gapNote = nil
            return
        }

        let points = inRange.map { TimelinePoint(at: $0.at, value: $0.value(for: metric)?.chartValue ?? 0) }
        // 按分段号切段；段内再按大间隔再切，避免把几小时的空档画成斜线。
        var bands: [TimelineBand] = []
        for (index, observation) in inRange.enumerated() {
            let point = points[index]
            if var last = bands.last, last.segment == observation.segment, !Self.isGap(last.points.last, point, range: range) {
                last = TimelineBand(segment: last.segment, points: last.points + [point])
                bands[bands.count - 1] = last
            } else {
                bands.append(TimelineBand(segment: observation.segment, points: [point]))
            }
        }
        self.bands = bands.filter { !$0.points.isEmpty }
        yRange = Self.range(for: points, isBalance: metric.isBalance)
        emptyReason = nil
        // 点是真的就画出来；只是跨度比历史还长时补一句，不假称已经看出中长期趋势。
        gapNote = Self.note(for: bands, range: range)
            ?? (range.isMeaningful(historyAge: historyAge) ? nil
                : "历史只有 \(Self.duration(historyAge))，" +
                  "\(range.label)这个跨度还看不出走势。")
    }

    /// 用“x 小时/x 天”描述历史长度，避免把秒数直接摆在界面上。
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(interval, 0)
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟" }
        if seconds < 86_400 { return "\(Int((seconds / 3_600).rounded())) 小时" }
        return "\(Int((seconds / 86_400).rounded())) 天"
    }

    static func currency(of metric: UsageHistoryMetric) -> String {
        if case .balance(let currency) = metric { return currency }
        return ""
    }

    static func isGap(_ previous: TimelinePoint?, _ next: TimelinePoint, range: UsageHistoryRange) -> Bool {
        guard let previous else { return false }
        let threshold = range.seconds / 24 * gapFactor
        return next.at.timeIntervalSince(previous.at) > threshold
    }

    /// 百分比固定 0–100 才有可比性；金额按实际最大值留一点余量。
    static func range(for points: [TimelinePoint], isBalance: Bool) -> ClosedRange<Double>? {
        guard let maxValue = points.map(\.value).max(), let minValue = points.map(\.value).min() else { return nil }
        if !isBalance { return 0...100 }
        let span = max(maxValue - minValue, max(maxValue * 0.1, 0.01))
        return max(0, minValue - span * 0.1)...(maxValue + span * 0.1)
    }

    static func note(for bands: [TimelineBand], range: UsageHistoryRange) -> String? {
        guard bands.count > 1 else { return nil }
        return "曲线分成 \(bands.count) 段：换个账户或密钥后读数不连续，所以不连成一条。"
    }
}

/// 把历史里出现过的指标转成可选择的标签，界面不自己拼字符串。
public enum UsageHistoryOptionBuilder {
    /// `labels` 提供窗口自定义名（比如厂商给的窗口标题），没给就用通用中文名。
    public static func options(for metrics: [UsageHistoryMetric],
                               labels: [String: String] = [:]) -> [UsageHistoryMetricOption] {
        metrics.map { metric in
            UsageHistoryMetricOption(metric: metric, label: label(for: metric, labels: labels))
        }
    }

    public static func label(for metric: UsageHistoryMetric, labels: [String: String] = [:]) -> String {
        switch metric {
        case .quota(let windowID):
            if let custom = labels[windowID], !custom.isEmpty { return custom }
            return windowID.contains("week") || windowID.contains("7") ? "周窗口" : "短期窗口"
        case .balance(let currency):
            return currency + " 余额"
        }
    }
}
