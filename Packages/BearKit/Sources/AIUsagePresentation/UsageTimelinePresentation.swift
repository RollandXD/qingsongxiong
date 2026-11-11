import AIUsageDomain
import Foundation

/// 时间线上的一段连续读数。分段号变化（换账户/换密钥）就断开，不把两段连成一条假曲线。
public struct TimelineBand: Equatable, Sendable, Identifiable {
    public let segment: Int
    public let points: [TimelinePoint]
    /// 同一账号分段内也可能有多次采样缺口，不能把 segment 单独当 SwiftUI 身份。
    public struct ID: Hashable, Sendable {
        let segment: Int
        let firstReading: Date?
    }
    public var id: ID { ID(segment: segment, firstReading: points.first?.at) }

    public init(segment: Int, points: [TimelinePoint]) {
        self.segment = segment
        self.points = points
    }
}

public struct TimelinePoint: Equatable, Sendable, Identifiable {
    public let at: Date
    /// 百分比（0–100）或金额；两者不混在同一张图里，由指标决定。
    public let value: Double
    /// 绘图用 Double，金额读数始终保留原始 Decimal，不把浮点舍入当原数。
    public let exactAmount: Decimal?
    public var id: Date { at }

    public init(at: Date, value: Double, exactAmount: Decimal? = nil) {
        self.at = at
        self.value = value
        self.exactAmount = exactAmount
    }

    public var fullValue: String {
        if let exactAmount { return NSDecimalNumber(decimal: exactAmount).stringValue }
        return value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
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

    /// 前台五分钟观测节奏下，连续超过十五分钟无读数就留缺口；不随缩放变成假连线。
    static let maximumContinuousInterval: TimeInterval = 15 * 60

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

        // 当前账户 session 的所有观测都参与断段；缺失指标不能先被过滤，否则会跨窗口/币种缺失连线。
        let session = archive.source(ref)?.segment
        let observations = archive.observations(for: ref).filter {
            $0.segment == session && $0.at >= now.addingTimeInterval(-range.seconds) && $0.at <= now
        }
        var bands: [TimelineBand] = []
        var currentSegment: Int?
        var currentPoints: [TimelinePoint] = []
        var previousReset: Date?
        for observation in observations {
            guard let entry = observation.entries.first(where: { $0.metric == metric }) else {
                if let segment = currentSegment { bands.append(TimelineBand(segment: segment, points: currentPoints)) }
                currentPoints = []; currentSegment = nil; previousReset = nil
                continue
            }
            let amount: Decimal?
            if case .amount(let value) = entry.value { amount = value } else { amount = nil }
            let point = TimelinePoint(at: observation.at, value: entry.value.chartValue, exactAmount: amount)
            if let segment = currentSegment,
               segment != observation.segment || previousReset != entry.resetsAt
                || Self.isGap(currentPoints.last, point, range: range) {
                bands.append(TimelineBand(segment: segment, points: currentPoints))
                currentPoints = []
            }
            currentSegment = observation.segment
            previousReset = entry.resetsAt
            currentPoints.append(point)
        }
        if let segment = currentSegment {
            bands.append(TimelineBand(segment: segment, points: currentPoints))
        }
        self.bands = bands
        yRange = Self.range(for: bands.flatMap(\.points), isBalance: metric.isBalance)
        emptyReason = nil
        // 点是真的就画出来；只是跨度比历史还长时补一句，不假称已经看出中长期趋势。
        let notes = [Self.note(for: bands, range: range),
                     range.isMeaningful(historyAge: historyAge) ? nil
                        : "历史只有 \(Self.duration(historyAge))，\(range.label)这个跨度还看不出走势。"]
            .compactMap { $0 }
        gapNote = notes.isEmpty ? nil : notes.joined(separator: " ")
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
        return next.at.timeIntervalSince(previous.at) > maximumContinuousInterval
    }

    /// 百分比固定 0–100 才有可比性；金额按实际最大值留一点余量。
    static func range(for points: [TimelinePoint], isBalance: Bool) -> ClosedRange<Double>? {
        guard let maxValue = points.map(\.value).max(), let minValue = points.map(\.value).min() else { return nil }
        if !isBalance { return 0...100 }
        let span = max(maxValue - minValue, max(max(abs(maxValue), abs(minValue)) * 0.1, 0.01))
        // 余额可以为负；不能把下界截到 0，否则全负区间会构造反向 ClosedRange 并崩溃。
        return (minValue - span * 0.1)...(maxValue + span * 0.1)
    }

    static func note(for bands: [TimelineBand], range: UsageHistoryRange) -> String? {
        guard bands.count > 1 else { return nil }
        return "曲线分成 \(bands.count) 段：采样缺口或账户、密钥、周期变化处保留断线，不补齐未知读数。"
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
