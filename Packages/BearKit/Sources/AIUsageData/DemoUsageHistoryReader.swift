#if DEBUG
import AIUsageDomain
import Foundation

/// 仅供 Debug 模拟器/截图：生成一段可复现的历史，让时间线在演示与 UI 测试里不是空图。
/// 不读文件、不读钥匙串、不访问网络。
public struct DemoUsageHistoryReader: UsageHistoryReading {
    private let anchor: Date
    private let scenario: String

    public init(scenario: String = "normal", now: Date = Date()) {
        self.scenario = scenario
        anchor = now
    }

    public func archive() async throws -> UsageHistoryArchive {
        switch scenario {
        case "history-error":
            throw UsageFailure.unavailable
        case "no-history":
            return .empty(at: anchor)
        case "short-history":
            return makeArchive(days: 0.12, interval: 900)
        default:
            return makeArchive(days: 30, interval: 3_600)
        }
    }

    /// 每个采样点按各自的窗口走一遍“匀速消耗”，所以曲线单调下降但重置处会跳回高位。
    private func makeArchive(days: Double, interval: TimeInterval) -> UsageHistoryArchive {
        let span = days * 86_400
        let step = max(interval, 300)
        var sources: [UsageHistorySource] = []
        for (index, provider) in [ProviderID.codex, .claude].enumerated() {
            let windows: [(String, Double)] = provider == .codex
                ? [("rate_limit.primary_window", 5 * 3_600.0), ("rate_limit.secondary_window", 7 * 86_400.0)]
                : [("five_hour", 5 * 3_600.0), ("seven_day", 7 * 86_400.0)]
            var observations: [UsageObservation] = []
            var time = anchor.addingTimeInterval(-span)
            while time <= anchor {
                let entries: [HistoryEntry] = windows.map { id, period in
                    let remaining = Self.remaining(at: time, period: period, seed: Double(index) + 1)
                    return HistoryEntry(metric: .quota(windowID: id), value: .percent(remaining))
                }
                observations.append(UsageObservation(at: time, segment: 0, entries: entries))
                time = time.addingTimeInterval(step)
            }
            sources.append(UsageHistorySource(source: .provider(provider), observations: observations))
        }
        sources.append(balanceSource(.provider(.deepseek), span: span, step: step,
                                     values: [("CNY", Decimal(string: "128.36")!), ("USD", 8)]))
        sources.append(balanceSource(.relay(UUID(uuidString: "11111111-2222-3333-4444-555555555555")!),
                                     span: span, step: step, values: [("USD", Decimal(string: "12.34567890123456789")!)]))
        return UsageHistoryArchive(sources: sources, updatedAt: anchor)
    }

    private func balanceSource(_ ref: AccountRef, span: TimeInterval, step: TimeInterval,
                               values: [(String, Decimal)]) -> UsageHistorySource {
        var observations: [UsageObservation] = []
        var time = anchor.addingTimeInterval(-span)
        while time <= anchor {
            let elapsed = Decimal(Int(anchor.timeIntervalSince(time) / step)) / 100
            let entries = values.map { unit, value in
                HistoryEntry(metric: .balance(currency: unit), value: .amount(value + elapsed))
            }
            observations.append(UsageObservation(at: time, segment: 0, entries: entries))
            time = time.addingTimeInterval(step)
        }
        return UsageHistorySource(source: ref, observations: observations)
    }

    /// 固定相位，不随机：同样的时间点永远得到同样的数，截图才可复现。
    static func remaining(at date: Date, period: TimeInterval, seed: Double) -> Double {
        let phase = (date.timeIntervalSince1970 + seed * 1_237).truncatingRemainder(dividingBy: period) / period
        // 0 → 100%，随相位下降；留一点噪声让曲线不像直尺画的。
        let base = 100 * (1 - phase)
        let wiggle = 6 * sin(phase * 12 + seed)
        return max(0, min(100, base + wiggle))
    }
}
#endif
