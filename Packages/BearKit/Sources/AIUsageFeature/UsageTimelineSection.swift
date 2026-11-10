import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

/// 过去用量：跨度/指标可切换，点按读数，断段与空态都说清原因。
struct UsageTimelineSection: View {
    let model: AIUsageModel
    let now: Date
    /// 主卡第一张决定默认看谁的历史；没有主卡就退回第一个已连接账户。
    let primary: AccountRef?

    @State private var range: UsageHistoryRange = .day
    @State private var chosenMetric: UsageHistoryMetric?
    @State private var selection: Date?
    @Environment(\.colorScheme) private var scheme

    private var options: [UsageHistoryMetricOption] {
        guard let primary else { return [] }
        return UsageHistoryOptionBuilder.options(for: model.history.metrics(for: primary))
    }

    private var metric: UsageHistoryMetric? {
        if let chosenMetric, options.contains(where: { $0.metric == chosenMetric }) { return chosenMetric }
        return options.first?.metric
    }

    private var presentation: UsageTimelinePresentation? {
        guard let primary, let metric else { return nil }
        let label = options.first { $0.metric == metric }?.label ?? ""
        return UsageTimelinePresentation(archive: model.history, ref: primary, metric: metric,
                                          range: range, now: now, metricLabel: label)
    }

    private var accent: Color { BearTheme.series(0, scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let presentation {
                chart(presentation)
                if let note = presentation.gapNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(BearTheme.secondaryText(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("timeline-note")
                }
            } else {
                Text(TimelineEmptyReason.noHistory.text)
                    .font(.footnote)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("timeline-empty")
            }
        }
        .padding(16)
        .background(BearTheme.surface(scheme), in: .rect(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("usage-timeline")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("过去用量").font(.footnote.weight(.semibold))
                Spacer()
                if let metric, options.count > 1 {
                    Menu {
                        ForEach(options) { option in
                            Button(option.label) { chosenMetric = option.metric }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(label(for: metric)).font(.footnote)
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                    }
                    .accessibilityIdentifier("timeline-metric")
                } else if let metric {
                    Text(label(for: metric)).font(.footnote).monospacedDigit()
                }
            }
            .foregroundStyle(BearTheme.secondaryText(scheme))
            Picker("跨度", selection: $range) {
                ForEach(UsageHistoryRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("timeline-range")
        }
    }

    private func label(for metric: UsageHistoryMetric) -> String {
        options.first { $0.metric == metric }?.label ?? ""
    }

    @ViewBuilder
    private func chart(_ presentation: UsageTimelinePresentation) -> some View {
        if presentation.isEmpty, let reason = presentation.emptyReason {
            Text(reason.text)
                .font(.footnote)
                .foregroundStyle(BearTheme.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("timeline-empty")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                reading(presentation)
                TimelineCanvas(presentation: presentation, now: now, selection: $selection,
                               accent: accent, reference: pacePath(presentation))
                    .frame(height: 132)
                    .accessibilityElement()
                    .accessibilityLabel("过去\(range.label)的" + presentation.metricLabel + "走势")
                    .accessibilityValue(readingText(presentation))
                    .accessibilityHint("左右滑动查看每个读数")
                    .accessibilityIdentifier("timeline-chart")
            }
        }
    }

    /// 当前读数或选中的历史读数；没有选点就显示最新值。
    @ViewBuilder
    private func reading(_ presentation: UsageTimelinePresentation) -> some View {
        let point = selectedPoint(presentation) ?? presentation.bands.last?.points.last
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let point {
                Text(format(point.value, isBalance: presentation.isBalance))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(presentation.isBalance ? presentation.unitLabel : "%")
                    .font(.footnote)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
                Spacer()
                Text(selection == nil ? "最新" : point.at.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
            }
        }
        .accessibilityIdentifier("timeline-reading")
    }

    private func readingText(_ presentation: UsageTimelinePresentation) -> String {
        let point = selectedPoint(presentation) ?? presentation.bands.last?.points.last
        guard let point else { return "没有读数" }
        let unit = presentation.isBalance ? presentation.unitLabel : "%"
        return format(point.value, isBalance: presentation.isBalance) + unit
    }

    private func selectedPoint(_ presentation: UsageTimelinePresentation) -> TimelinePoint? {
        guard let selection else { return nil }
        return presentation.bands.flatMap(\.points).min {
            abs($0.at.timeIntervalSince(selection)) < abs($1.at.timeIntervalSince(selection))
        }
    }

    private func format(_ value: Double, isBalance: Bool) -> String {
        if isBalance { return value.formatted(.number.precision(.fractionLength(2))) }
        return value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }

    /// 配速参考线：从窗口开始时的 100% 匀速降到重置时刻的 0%。
    /// 只裁出落在当前跨度里的那一段；余额没有“重置”，不画。
    private func pacePath(_ presentation: UsageTimelinePresentation) -> PacePath? {
        guard !presentation.isBalance, case .quota(let windowID) = metric,
              let primary, case .provider(let provider) = primary,
              let state = model.states[provider],
              let window = state.snapshot?.windows.first(where: { $0.id == windowID }),
              let pace = try? QuotaPaceCalculator.pace(for: window, now: now),
              pace.periodStart < now else { return nil }
        let visibleEnd = now
        let visibleStart = now.addingTimeInterval(-range.seconds)
        let start = max(pace.periodStart, visibleStart)
        let end = min(pace.resetsAt, now)
        guard end > start else { return nil }
        // 参考线：重置时刻剩 0%，窗口开始时剩 100%。
        let total = pace.resetsAt.timeIntervalSince(pace.periodStart)
        guard total > 0 else { return nil }
        func remaining(_ date: Date) -> Double {
            max(0, min(100, 100 * pace.resetsAt.timeIntervalSince(date) / total))
        }
        return PacePath(start: start, end: min(end, visibleEnd),
                        startValue: remaining(start), endValue: remaining(min(end, visibleEnd)),
                        comparison: pace.comparison)
    }
}

/// 参考线的两个端点与说明；`nil` 表示这个指标/窗口不该画参考线。
struct PacePath: Equatable {
    let start: Date
    let end: Date
    let startValue: Double
    let endValue: Double
    let comparison: String
}

/// 手绘折线：不做插值、不在缺口处连线，和蜜罐的线稿风格一致。
struct TimelineCanvas: View {
    let presentation: UsageTimelinePresentation
    let now: Date
    @Binding var selection: Date?
    let accent: Color
    let reference: PacePath?

    private var domain: (start: Date, end: Date) {
        (now.addingTimeInterval(-presentation.range.seconds), now)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let inset = EdgeInsets(top: 8, leading: 2, bottom: 18, trailing: 2)
            ZStack(alignment: .topLeading) {
                grid(size, inset)
                ForEach(presentation.bands) { band in
                    line(band, size, inset)
                }
                if let reference {
                    referenceLine(reference, size, inset)
                }
                if let selection, let point = nearestPoint(selection) {
                    marker(point, size, inset)
                }
                axisLabels(size, inset)
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selection = date(atX: value.location.x, size: size, inset: inset)
                    }
            )
        }
    }

    private func x(_ date: Date, _ size: CGSize, _ inset: EdgeInsets) -> CGFloat {
        let span = domain.end.timeIntervalSince(domain.start)
        let ratio = span > 0 ? date.timeIntervalSince(domain.start) / span : 1
        return inset.leading + (size.width - inset.leading - inset.trailing) * min(max(ratio, 0), 1)
    }

    private func y(_ value: Double, _ size: CGSize, _ inset: EdgeInsets) -> CGFloat {
        let bounds = presentation.yRange ?? 0...100
        let span = bounds.upperBound - bounds.lowerBound
        let ratio = span > 0 ? (value - bounds.lowerBound) / span : 0.5
        return inset.top + (size.height - inset.top - inset.bottom) * (1 - min(max(ratio, 0), 1))
    }

    private func date(atX location: CGFloat, size: CGSize, inset: EdgeInsets) -> Date {
        let width = max(size.width - inset.leading - inset.trailing, 1)
        let ratio = min(max((location - inset.leading) / width, 0), 1)
        return domain.start.addingTimeInterval(domain.end.timeIntervalSince(domain.start) * ratio)
    }

    private func nearestPoint(_ date: Date) -> TimelinePoint? {
        presentation.bands.flatMap(\.points).min {
            abs($0.at.timeIntervalSince(date)) < abs($1.at.timeIntervalSince(date))
        }
    }

    private func line(_ band: TimelineBand, _ size: CGSize, _ inset: EdgeInsets) -> some View {
        let points = band.points
        return Path { path in
            for (index, point) in points.enumerated() {
                let position = CGPoint(x: x(point.at, size, inset), y: y(point.value, size, inset))
                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
            }
            if points.count == 1, let only = points.first {
                let position = CGPoint(x: x(only.at, size, inset), y: y(only.value, size, inset))
                path.addEllipse(in: CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4))
            }
        }
        .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    private func referenceLine(_ path: PacePath, _ size: CGSize, _ inset: EdgeInsets) -> some View {
        let start = CGPoint(x: x(path.start, size, inset), y: y(path.startValue, size, inset))
        let end = CGPoint(x: x(path.end, size, inset), y: y(path.endValue, size, inset))
        return Path { line in
            line.move(to: start)
            line.addLine(to: end)
        }
        .stroke(BearTheme.secondaryText(.light).opacity(0.45),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
    }

    private func marker(_ point: TimelinePoint, _ size: CGSize, _ inset: EdgeInsets) -> some View {
        let position = CGPoint(x: x(point.at, size, inset), y: y(point.value, size, inset))
        return ZStack {
            Rectangle()
                .fill(BearTheme.secondaryText(.light).opacity(0.25))
                .frame(width: 1)
                .position(x: position.x, y: size.height / 2)
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .position(position)
        }
        .allowsHitTesting(false)
    }

    private func grid(_ size: CGSize, _ inset: EdgeInsets) -> some View {
        Path { path in
            for ratio in [0.0, 0.5, 1.0] {
                let y = inset.top + (size.height - inset.top - inset.bottom) * ratio
                path.move(to: CGPoint(x: inset.leading, y: y))
                path.addLine(to: CGPoint(x: size.width - inset.trailing, y: y))
            }
        }
        .stroke(BearTheme.secondaryText(.light).opacity(0.12), lineWidth: 0.5)
    }

    /// 只标起止时间：轴上多几个刻度，小屏和大字下就会互相压字。
    private func axisLabels(_ size: CGSize, _ inset: EdgeInsets) -> some View {
        ZStack(alignment: .topLeading) {
            Text(domain.start.formatted(date: .omitted, time: .shortened))
                .position(x: inset.leading + 22, y: size.height - 6)
            Text("现在")
                .position(x: size.width - inset.trailing - 14, y: size.height - 6)
        }
        .font(.caption2)
        .foregroundStyle(BearTheme.secondaryText(.light).opacity(0.8))
        .allowsHitTesting(false)
    }
}
