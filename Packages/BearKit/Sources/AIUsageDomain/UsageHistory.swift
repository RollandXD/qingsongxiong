import BearFoundation
import Foundation

/// 一条历史指标：额度窗口的剩余百分比，或某币种的余额金额。
public enum UsageHistoryMetric: Codable, Equatable, Hashable, Sendable {
    case quota(windowID: String)
    case balance(currency: String)

    /// 同一指标内部的稳定键，用于比较与去重。
    public var stableKey: String {
        switch self {
        case .quota(let id): "quota:" + id
        case .balance(let currency): "balance:" + currency
        }
    }

    public var isBalance: Bool {
        switch self {
        case .quota: false
        case .balance: true
        }
    }
}

/// 采样值。百分比用 `Double`，金额保留精确 `Decimal`——
/// 图表坐标可以转成数值，但标签显示的真实金额不能被浮点改写。
public enum HistoryValue: Codable, Equatable, Sendable {
    case percent(Double)
    case amount(Decimal)

    /// 仅用于画图与比较，不作为金额展示。
    public var chartValue: Double {
        switch self {
        case .percent(let value): value.isFinite ? value : 0
        case .amount(let value): NSDecimalNumber(decimal: value).doubleValue
        }
    }
}

public struct HistoryEntry: Codable, Equatable, Sendable {
    public let metric: UsageHistoryMetric
    public let value: HistoryValue

    public init(metric: UsageHistoryMetric, value: HistoryValue) {
        self.metric = metric
        self.value = value
    }
}

/// 一次成功刷新的观测。同一次刷新里的所有窗口/币种属于同一时刻、同一分段。
public struct UsageObservation: Codable, Equatable, Sendable {
    public let at: Date
    /// 账户/密钥/接口切换后递增，用来在曲线上断开而不是连成一条假趋势。
    public let segment: Int
    public let entries: [HistoryEntry]

    public init(at: Date, segment: Int, entries: [HistoryEntry]) {
        self.at = at
        self.segment = segment
        self.entries = entries
    }

    public func value(for metric: UsageHistoryMetric) -> HistoryValue? {
        entries.first { $0.metric == metric }?.value
    }

    public var metrics: [UsageHistoryMetric] { entries.map(\.metric) }
}

public struct UsageHistorySource: Codable, Equatable, Sendable {
    public let source: AccountRef
    /// 当前分段号；账户/密钥/接口切换后递增，旧观测保留原分段号，不会被改写。
    public let segment: Int
    public var observations: [UsageObservation]

    public init(source: AccountRef, observations: [UsageObservation], segment: Int = 0) {
        self.source = source
        self.segment = segment
        self.observations = observations
    }

    private enum CodingKeys: String, CodingKey { case source, segment, observations }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let observations = try values.decode([UsageObservation].self, forKey: .observations)
        self.init(source: try values.decode(AccountRef.self, forKey: .source),
                  observations: observations,
                  segment: try values.decodeIfPresent(Int.self, forKey: .segment)
                      ?? observations.map(\.segment).max() ?? 0)
    }
}

/// 设备本地的“刷新时观测到的额度/余额”，不是逐请求账单。
///
/// 只记录成功提交之后的观测；不上传、不写凭据、不补齐没取得的历史。
public struct UsageHistoryArchive: TimestampedRecord, Equatable, Sendable {
    public static let schemaRevision = 1
    /// 保留最近 30 天。
    public static let retention: TimeInterval = 30 * 24 * 3_600
    /// 每个来源最多 10,000 次观测（约 5 分钟一次的前台节奏可以用满 30 天）。
    public static let sourceObservationLimit = 10_000
    /// 本地文件总预算；超出后从最老的观测开始删，而不是无限长。
    public static let maximumBytes = 4 * 1_024 * 1_024

    public let revision: Int
    public let sources: [UsageHistorySource]
    public let updatedAt: Date

    public init(sources: [UsageHistorySource], updatedAt: Date, revision: Int = UsageHistoryArchive.schemaRevision) {
        self.sources = sources
        self.updatedAt = updatedAt
        self.revision = revision
    }

    public static func empty(at date: Date) -> UsageHistoryArchive {
        UsageHistoryArchive(sources: [], updatedAt: date)
    }

    private enum CodingKeys: String, CodingKey { case revision, sources, updatedAt }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sources: try values.decode([UsageHistorySource].self, forKey: .sources),
                  updatedAt: try values.decode(Date.self, forKey: .updatedAt),
                  revision: try values.decodeIfPresent(Int.self, forKey: .revision) ?? Self.schemaRevision)
    }

    public func source(_ ref: AccountRef) -> UsageHistorySource? {
        sources.first { $0.source == ref }
    }

    public func observations(for ref: AccountRef) -> [UsageObservation] {
        source(ref)?.observations ?? []
    }

    /// 某个指标的观测序列，保持时间升序；缺该指标的观测不补点。
    public func series(for ref: AccountRef, metric: UsageHistoryMetric) -> [UsageObservation] {
        self.source(ref)?.observations.filter { $0.value(for: metric) != nil } ?? []
    }

    /// 该来源出现过的全部指标，按首次出现顺序（额度先后、币种先后）。
    public func metrics(for ref: AccountRef) -> [UsageHistoryMetric] {
        var seen = Set<String>()
        var result: [UsageHistoryMetric] = []
        for observation in observations(for: ref) {
            for metric in observation.metrics where seen.insert(metric.stableKey).inserted {
                result.append(metric)
            }
        }
        return result
    }

    /// 时间窗口内的序列，端点包含在内。
    public func series(for ref: AccountRef, metric: UsageHistoryMetric,
                       in range: UsageHistoryRange, now: Date) -> [UsageObservation] {
        let start = now.addingTimeInterval(-range.seconds)
        return series(for: ref, metric: metric).filter { $0.at >= start && $0.at <= now }
    }
}

/// 时间线只需要“读”。放在 Domain，界面层不依赖 Data 也能拿到历史。
public protocol UsageHistoryReading: Sendable {
    func archive() async throws -> UsageHistoryArchive
}

/// 历史里出现过的指标，用于让界面选择“看哪个窗口/币种”。
public struct UsageHistoryMetricOption: Identifiable, Equatable, Sendable {
    public let metric: UsageHistoryMetric
    public let label: String
    public var id: String { metric.stableKey }

    public init(metric: UsageHistoryMetric, label: String) {
        self.metric = metric
        self.label = label
    }
}

/// 时间线可选的回看跨度。名称与秒数固定，不在界面临时硬编码。
public enum UsageHistoryRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case day, week, month

    public var id: String { rawValue }

    public var seconds: TimeInterval {
        switch self {
        case .day: 24 * 3_600
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        }
    }

    public var label: String {
        switch self {
        case .day: "24 小时"
        case .week: "7 天"
        case .month: "30 天"
        }
    }

    /// 有足够长的历史才值得给这个跨度，避免空图假装有趋势。
    public func isMeaningful(historyAge: TimeInterval) -> Bool {
        historyAge >= seconds / 4
    }
}

/// 历史归约的写入结果，供调用方区分“真写进去了”和“被丢弃但不算错”。
public enum UsageHistoryWriteOutcome: Equatable, Sendable {
    /// 新增了一条观测。
    case appended
    /// 同一分段同一秒重复写：原地更新，不产生重复点。
    case replaced
    /// 比保留窗口还旧，直接丢弃。
    case discardedTooOld
    /// 内容与已有点完全一致，没改动。
    case unchanged

    public var didChange: Bool {
        switch self {
        case .appended, .replaced: true
        case .discardedTooOld, .unchanged: false
        }
    }
}

/// 纯归约：不管文件、不管并发，只描述“归档该怎么变”，方便单独验证去重/分段/裁剪。
public enum UsageHistoryReducer {
    /// 同一秒内的同指标点视为同一次刷新。
    private static let dedupeInterval: TimeInterval = 1

    public static func recording(_ observation: UsageObservation, for ref: AccountRef,
                                 in archive: UsageHistoryArchive,
                                 now: Date) -> (archive: UsageHistoryArchive, outcome: UsageHistoryWriteOutcome) {
        guard !observation.entries.isEmpty else { return (archive, .unchanged) }
        let cutoff = now.addingTimeInterval(-UsageHistoryArchive.retention)
        guard observation.at >= cutoff else { return (archive, .discardedTooOld) }

        var observations = archive.observations(for: ref)
        // 分段号以来源上的计数器为准：刚开新段时观测里还没有新段号，不能从观测反推。
        let segment = archive.source(ref)?.segment ?? existingSegment(observations: observations,
                                                                      fallback: observation.segment)
        let stamped = UsageObservation(at: observation.at, segment: segment, entries: observation.entries)

        // 迟到写回：找到同一分段、同一秒内的已有观测，就把指标并进去，而不是插一条重复点。
        if let index = observations.lastIndex(where: {
            $0.segment == segment && abs($0.at.timeIntervalSince(observation.at)) <= dedupeInterval
        }) {
            let merged = merging(observations[index], with: stamped)
            guard merged.entries != observations[index].entries else { return (archive, .unchanged) }
            observations[index] = merged
            return (replacing(observations, for: ref, in: archive, now: now), .replaced)
        }

        observations.append(stamped)
        observations.sort { $0.at < $1.at }
        return (replacing(observations, for: ref, in: archive, now: now), .appended)
    }

    /// 账户切换：只递增分段号，旧观测原样保留（曲线断开而不是假装连续）。
    public static func beginningSegment(for ref: AccountRef, in archive: UsageHistoryArchive,
                                        now: Date) -> UsageHistoryArchive {
        let observations = archive.observations(for: ref)
        let current = existingSegment(observations: observations, fallback: 0)
        return replacing(observations, for: ref, in: archive, now: now, segment: current + 1)
    }

    /// 隐私清除：删掉某个来源的全部历史；没这个来源时原样返回。
    public static func forgetting(_ ref: AccountRef, in archive: UsageHistoryArchive,
                                  now: Date) -> UsageHistoryArchive {
        guard archive.sources.contains(where: { $0.source == ref }) else { return archive }
        let kept = archive.sources.filter { $0.source != ref }
        return UsageHistoryArchive(sources: kept, updatedAt: now)
    }

    /// 有界裁剪：按保留期丢弃老点，再按每来源上限保留最新，最后卡总字节预算。
    public static func pruned(_ archive: UsageHistoryArchive, now: Date,
                              byteBudget: Int = UsageHistoryArchive.maximumBytes) -> UsageHistoryArchive {
        let cutoff = now.addingTimeInterval(-UsageHistoryArchive.retention)
        var sources = archive.sources.map { source -> UsageHistorySource in
            var observations = source.observations.filter { $0.at >= cutoff }
            if observations.count > UsageHistoryArchive.sourceObservationLimit {
                observations = Array(observations.suffix(UsageHistoryArchive.sourceObservationLimit))
            }
            return UsageHistorySource(source: source.source, observations: observations, segment: source.segment)
        }.filter { !$0.observations.isEmpty }

        // 还超预算就按“最老观测”优先删，尽量保住各来源最近的点。
        var archive = UsageHistoryArchive(sources: sources, updatedAt: archive.updatedAt)
        var iterations = 0
        while estimatedBytes(archive) > byteBudget, iterations < 10_000 {
            guard let victim = sources.indices.min(by: {
                (sources[$0].observations.first?.at ?? .distantFuture) < (sources[$1].observations.first?.at ?? .distantFuture)
            }) else { break }
            var observations = sources[victim].observations
            guard !observations.isEmpty else { break }
            let drop = max(1, observations.count / 8)
            observations.removeFirst(min(drop, observations.count))
            sources[victim] = UsageHistorySource(source: sources[victim].source,
                                                 observations: observations,
                                                 segment: sources[victim].segment)
            sources = sources.filter { !$0.observations.isEmpty }
            archive = UsageHistoryArchive(sources: sources, updatedAt: archive.updatedAt)
            iterations += 1
        }
        return archive
    }

    /// 粗估编码后大小，只用来守预算，不追求与 JSON 字节数一致。
    public static func estimatedBytes(_ archive: UsageHistoryArchive) -> Int {
        archive.sources.reduce(0) { total, source in
            total + source.observations.reduce(64) { $0 + 32 + $1.entries.count * 24 }
        }
    }

    private static func existingSegment(observations: [UsageObservation], fallback: Int) -> Int {
        observations.map(\.segment).max() ?? fallback
    }

    private static func merging(_ existing: UsageObservation, with incoming: UsageObservation) -> UsageObservation {
        var entries = existing.entries
        for entry in incoming.entries {
            if let index = entries.firstIndex(where: { $0.metric == entry.metric }) {
                entries[index] = entry
            } else {
                entries.append(entry)
            }
        }
        return UsageObservation(at: min(existing.at, incoming.at), segment: existing.segment, entries: entries)
    }

    private static func replacing(_ observations: [UsageObservation], for ref: AccountRef,
                                 in archive: UsageHistoryArchive, now: Date,
                                 segment: Int? = nil) -> UsageHistoryArchive {
        // 计数器只增不减：即便新段的观测被裁剪掉，也不能退回旧段号。
        let observed = observations.map(\.segment).max() ?? 0
        let current = max(segment ?? 0, max(observed, archive.source(ref)?.segment ?? 0))
        let updated = UsageHistorySource(source: ref, observations: observations, segment: current)
        var sources = archive.sources
        if let index = sources.firstIndex(where: { $0.source == ref }) {
            sources[index] = updated
        } else {
            sources.append(updated)
        }
        return UsageHistoryArchive(sources: sources, updatedAt: now)
    }
}
