import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI
import WidgetKit

// 蜜罐小组件：与 App 首页同一套视觉语言。HoneyJarPresentation.cells 在 AIUsageFeature 内是 internal，
// Widget 不得依赖该模块，所以这里用等价的私有实现；液体直接用 BearDesignSystem 的 HoneyLiquidShape。

private struct WidgetJarCell: Equatable {
    let level: Double
    let warn: Bool
    let value: String?
    let label: String
}

private struct ResetHint {
    let name: String
    let remaining: Double
    let reset: Date
}

private extension HoneyJarPresentation {
    var slots: [(name: String, window: UsageWindowPresentation?)] {
        [(name: "5 小时", window: fiveHour), (name: "本周", window: weekly)]
    }

    func widgetCells(now: Date) -> [WidgetJarCell] {
        var result: [WidgetJarCell] = []
        for slot in slots {
            guard let window = slot.window, isConnected else {
                result.append(WidgetJarCell(level: 0, warn: false, value: nil, label: slot.name))
                continue
            }
            let remaining = ScrubForecast.remainingPercent(window, now: now, offset: 0)
            result.append(WidgetJarCell(
                level: min(1, max(0, remaining / 100)),
                warn: QuotaThresholds.level(remainingPercent: remaining) != .normal,
                value: String(Int(remaining.rounded())), label: slot.name))
        }
        return result
    }

    /// 两格里最紧、且还会重置的窗口；已满（100%）的窗口没有「回满」可言。
    func tightestReset(now: Date) -> ResetHint? {
        guard isConnected else { return nil }
        var best: ResetHint?
        for slot in slots {
            guard let window = slot.window, let reset = window.window.resetsAt, reset > now, window.remaining < 100 else { continue }
            let hint = ResetHint(name: slot.name, remaining: window.remaining, reset: reset)
            if let current = best {
                if hint.remaining < current.remaining || (hint.remaining == current.remaining && hint.reset < current.reset) { best = hint }
            } else { best = hint }
        }
        return best
    }

    var allFull: Bool {
        let known = slots.compactMap { $0.window }
        return isConnected && !known.isEmpty && known.allSatisfy { $0.remaining >= 100 }
    }

    var widgetSummary: String {
        guard isConnected else { return ProviderPresentation.name(provider) + "，未连接" }
        let parts = slots.compactMap { slot -> String? in
            guard let window = slot.window else { return nil }
            return slot.name + "剩 " + ProviderPresentation.percent(window.remaining)
        }
        return ProviderPresentation.name(provider) + "，" + parts.joined(separator: "，")
    }
}

/// 「2天」「5小时」「12分钟」，锁屏单行空间紧，用粗粒度。
private func coarseSpan(_ interval: TimeInterval) -> String {
    let seconds = Int(interval.isFinite ? min(max(0, interval), 3_153_600_000) : 0)
    if seconds >= 86_400 { return "\(seconds / 86_400)天" }
    if seconds >= 3_600 { return "\(seconds / 3_600)小时" }
    return "\(max(1, seconds / 60))分钟"
}

/// 小组件里的迷你罐：无状态、无逐帧驱动。液体可着色（widgetAccentable），数字与标签是文字层。
private struct WidgetJar: View {
    let cells: [WidgetJarCell]
    let stale: Bool
    let asleep: Bool
    let cornerRadius: CGFloat
    let numberSize: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var monochrome: Bool { renderingMode != .fullColor }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        HStack(spacing: 3) {
            ForEach(cells.indices, id: \.self) { index in
                ZStack {
                    Rectangle().fill(monochrome ? Color.primary.opacity(0.14) : BearTheme.track(scheme))
                    liquid(cells[index])
                    labels(cells[index])
                }
            }
        }
        .background(monochrome ? Color.clear : BearTheme.surface(scheme))
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(monochrome ? Color.primary.opacity(0.25) : BearTheme.separator(scheme),
                               style: StrokeStyle(lineWidth: 0.5, dash: asleep ? [4, 5] : []))
        }
        .accessibilityHidden(true)
    }

    private func liquid(_ cell: WidgetJarCell) -> some View {
        let level = asleep ? 0 : cell.level
        return ZStack {
            HoneyLiquidShape(level: level, slosh: 2)
                .fill(fillStyle(cell))
                .widgetAccentable()
            HoneyLiquidShape(level: level, slosh: 2, surfaceOnly: true)
                .stroke(Color.white.opacity(scheme == .dark ? 0.35 : 0.7), lineWidth: 1.5)
                .opacity(level > 0.03 && !monochrome ? 1 : 0)
        }
        .saturation(stale ? 0.2 : 1)
        .opacity(stale ? 0.5 : 1)
    }

    private func fillStyle(_ cell: WidgetJarCell) -> AnyShapeStyle {
        if monochrome { return AnyShapeStyle(Color.primary.opacity(0.42)) }
        let colors = cell.warn ? BearTheme.ember(scheme) : BearTheme.honey(scheme)
        return AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
    }

    private func labels(_ cell: WidgetJarCell) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(asleep ? "–" : cell.value ?? "–")
                    .font(.system(size: numberSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(numberColor(cell))
                    .contentTransition(.numericText())
                if !asleep && cell.value != nil {
                    Text("%").font(.system(size: numberSize * 0.43, weight: .bold, design: .rounded))
                        .foregroundStyle(monochrome ? Color.primary.opacity(0.72) : BearTheme.secondaryText(scheme))
                }
            }
            .lineLimit(1).minimumScaleFactor(0.5)
            Spacer(minLength: 0)
            Text(cell.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(labelColor(cell))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.top, 8).padding(.bottom, 7).padding(.horizontal, 2)
    }

    private func numberColor(_ cell: WidgetJarCell) -> Color {
        if monochrome { return .primary }
        return cell.warn && !asleep ? BearTheme.danger(scheme) : BearTheme.text(scheme)
    }

    private func labelColor(_ cell: WidgetJarCell) -> Color {
        if monochrome { return .primary }
        if asleep || cell.level < 0.16 { return BearTheme.secondaryText(scheme) }
        return cell.warn ? .white : BearTheme.honeyInk(scheme)
    }
}

/// 横条：DeepSeek「赠送 / 充值」占比用，液体同样可着色。
private struct WidgetBar: View {
    let fraction: Double
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(renderingMode == .fullColor ? BearTheme.track(scheme) : Color.primary.opacity(0.14))
                Capsule()
                    .fill(renderingMode == .fullColor
                          ? AnyShapeStyle(LinearGradient(colors: BearTheme.honey(scheme), startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.primary.opacity(0.5)))
                    .frame(width: max(fraction > 0 ? geometry.size.height : 0, geometry.size.width * min(1, max(0, fraction))))
                    .widgetAccentable()
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// App 的合成预览与 Widget 使用同一份布局，数据路径仍由各自组合根提供。
struct WidgetMetricContent: View {
    let states: [ProviderState]
    let provider: ProviderID?
    let date: Date
    let family: WidgetFamily
    let relays: [RelayState]
    let refreshControl: AnyView?
    init(states: [ProviderState], provider: ProviderID?, date: Date, family: WidgetFamily,
         relays: [RelayState] = [], refreshControl: AnyView? = nil) {
        self.states = states; self.provider = provider; self.date = date; self.family = family
        self.relays = relays; self.refreshControl = refreshControl
    }
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var monochrome: Bool { renderingMode != .fullColor }
    private var secondary: Color { monochrome ? .primary.opacity(0.72) : BearTheme.secondaryText(scheme) }
    private var ink: Color { monochrome ? .primary : BearTheme.text(scheme) }

    private var jars: [HoneyJarPresentation] {
        states.map { HoneyJarPresentation(ProviderDashboardPresentation(provider: $0.provider, state: $0, at: date)) }
    }
    private func honeyJar(for id: ProviderID) -> HoneyJarPresentation {
        if let found = jars.first(where: { $0.provider == id }) { return found }
        return HoneyJarPresentation(ProviderDashboardPresentation(provider: id, state: nil, at: date))
    }

    var body: some View {
        Group {
            if [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family) { accessory }
            else if let provider { single(honeyJar(for: provider)) }
            else { overview }
        }
    }

    // MARK: 主屏幕

    private var overview: some View {
        let large = family == .systemLarge
        let quota = jars.filter { $0.provider != .deepseek }
        return VStack(alignment: .leading, spacing: 8) {
            header(title: "AI 额度", dot: nil)
            HStack(alignment: .top, spacing: 12) {
                ForEach(quota, id: \.provider) { item in
                    overviewColumn(item, large: large)
                }
            }
            if large {
                Rectangle().fill(monochrome ? Color.primary.opacity(0.2) : BearTheme.separator(scheme)).frame(height: 0.5)
                balanceRow
            } else {
                nextRefillLine(quota)
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func overviewColumn(_ item: HoneyJarPresentation, large: Bool) -> some View {
        Link(destination: URL(string: "qingsongxiong://ai-usage/provider/" + item.provider.rawValue)!) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    providerDot(item.provider)
                    Text(ProviderPresentation.name(item.provider)).font(.caption.weight(.semibold)).foregroundStyle(ink).lineLimit(1)
                }.padding(.leading, 2)
                WidgetJar(cells: item.widgetCells(now: date), stale: item.dashboard.isStale && item.isConnected,
                          asleep: !item.isConnected, cornerRadius: large ? 20 : 16, numberSize: large ? 28 : 20)
                    .frame(maxHeight: .infinity)
                    .id(item.dashboard.state?.sessionID)
                if large { resetFooter(item).frame(maxWidth: .infinity) }
            }
        }
        .privacySensitive()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.widgetSummary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nextRefillLine(_ quota: [HoneyJarPresentation]) -> some View {
        var best: (jar: HoneyJarPresentation, hint: ResetHint)?
        for item in quota {
            guard let hint = item.tightestReset(now: date) else { continue }
            if let current = best {
                if hint.remaining < current.hint.remaining
                    || (hint.remaining == current.hint.remaining && hint.reset < current.hint.reset) { best = (item, hint) }
            } else { best = (item, hint) }
        }
        let pick = best
        let fallback = quota.contains { $0.allFull } ? "额度都满着" : quota.contains { $0.isConnected } ? "暂无重置时间" : "未连接"
        return HStack(spacing: 0) {
            Text("下一次回满：").foregroundStyle(secondary)
            if let pick {
                Text(ProviderPresentation.name(pick.jar.provider) + " " + pick.hint.name + " · "
                     + ResetCountdown.compact(pick.hint.reset.timeIntervalSince(date)))
                    .fontWeight(.semibold).foregroundStyle(ink).monospacedDigit()
            } else {
                Text(fallback).foregroundStyle(secondary)
            }
        }
        .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
        .privacySensitive()
    }

    private var balanceRow: some View {
        let deepseek = honeyJar(for: .deepseek)
        let first = deepseek.dashboard.balances.first
        return HStack(alignment: .top, spacing: 12) {
            balanceCell(title: "DeepSeek", currency: first?.balance.currency,
                        amount: first.map { NSDecimalNumber(decimal: $0.balance.total).stringValue })
            if let state = relays.first {
                let parts = RelayPresentation(state: state, at: date).widgetParts
                Link(destination: RelayPresentation.url(state.id)) {
                    balanceCell(title: state.account.displayName, currency: parts?.code, amount: parts?.amount)
                }
            }
        }
        .privacySensitive()
    }

    private func balanceCell(title: String, currency: String?, amount: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let currency { Text(currency).font(.caption2.weight(.semibold)).foregroundStyle(secondary) }
                Text(amount ?? "—").font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                    .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func single(_ item: HoneyJarPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(title: ProviderPresentation.name(item.provider), dot: item.provider)
            if item.provider == .deepseek {
                balanceBody(item.dashboard)
            } else if family == .systemMedium {
                HStack(alignment: .center, spacing: 14) {
                    miniJar(item, numberSize: 26).frame(maxWidth: 170)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(item.slots.enumerated()), id: \.offset) { entry in
                            slotLine(entry.element.name, entry.element.window, connected: item.isConnected)
                        }
                        timestamp(item.dashboard)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    miniJar(item, numberSize: 26).frame(maxHeight: .infinity)
                    resetFooter(item).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .privacySensitive()
        .accessibilityElement(children: .combine)
    }

    private func miniJar(_ item: HoneyJarPresentation, numberSize: CGFloat) -> some View {
        WidgetJar(cells: item.widgetCells(now: date), stale: item.dashboard.isStale && item.isConnected,
                  asleep: !item.isConnected, cornerRadius: 18, numberSize: numberSize)
            .id(item.dashboard.state?.sessionID)
    }

    private func slotLine(_ name: String, _ window: UsageWindowPresentation?, connected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(ink)
            Group {
                if !connected { Text("未连接") }
                else if let window, let reset = window.window.resetsAt {
                    if window.remaining >= 100 { Text("已满") }
                    else if reset > date { Text("回满 " + ResetCountdown.compact(reset.timeIntervalSince(date))).monospacedDigit() }
                    else { Text(ResetCountdown.moment(reset, now: date)) }
                } else { Text("—") }
            }.font(.caption2).foregroundStyle(secondary).lineLimit(1)
        }
    }

    private func balanceBody(_ value: ProviderDashboardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let balance = value.balances.first {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(balance.balance.currency).font(.caption.weight(.semibold)).foregroundStyle(secondary)
                    Text(NSDecimalNumber(decimal: balance.balance.total).stringValue)
                        .font(.system(size: family == .systemSmall ? 30 : 38, weight: .bold, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1).contentTransition(.numericText())
                        .id(balance.id)
                }
                if let parts = balance.parts {
                    WidgetBar(fraction: parts[0].fraction)
                    HStack {
                        Text("赠送 " + NSDecimalNumber(decimal: parts[0].amount).stringValue)
                        Spacer(minLength: 3)
                        Text("充值 " + NSDecimalNumber(decimal: parts[1].amount).stringValue)
                    }.font(.caption2).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            } else {
                Text(value.state?.connection == .connected ? "—" : "未连接")
                    .font(.system(.title2, design: .rounded).weight(.bold)).foregroundStyle(secondary)
            }
            Spacer(minLength: 0)
            timestamp(value)
        }
    }

    // MARK: 公共部件

    private func header(title: String, dot: ProviderID?) -> some View {
        HStack(spacing: 6) {
            if let dot { providerDot(dot) }
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(ink).lineLimit(1)
            Spacer(minLength: 4)
            if let refreshControl { refreshControl }
            else {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(monochrome ? Color.primary : BearTheme.accentInk(scheme))
                    .frame(width: 24, height: 24)
                    .background(monochrome ? Color.primary.opacity(0.14) : BearTheme.track(scheme), in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 24)
    }

    private func providerDot(_ id: ProviderID) -> some View {
        Circle().fill(monochrome ? Color.primary : BearTheme.series(ProviderPresentation.paletteIndex(id), scheme))
            .frame(width: 8, height: 8).widgetAccentable().accessibilityHidden(true)
    }

    private func resetFooter(_ item: HoneyJarPresentation) -> some View {
        HStack(spacing: 4) {
            if !item.isConnected { Text("未连接") }
            else if let hint = item.tightestReset(now: date) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(hint.name + " · " + ResetCountdown.compact(hint.reset.timeIntervalSince(date))).monospacedDigit()
            } else { Text(item.allFull ? "额度已满" : "—") }
        }
        .font(.caption2).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.8)
    }

    private func timestamp(_ value: ProviderDashboardPresentation) -> some View {
        HStack(spacing: 3) {
            if value.isStale && value.state?.snapshot != nil {
                Image(systemName: "clock.badge.exclamationmark").accessibilityHidden(true)
            }
            Text(value.status == "已同步" ? "更新于" : value.status)
            if let snapshot = value.state?.snapshot { Text(snapshot.fetchedAt, style: .time) }
        }.font(.caption2).foregroundStyle(secondary).lineLimit(1)
    }

    // MARK: 锁屏

    @ViewBuilder private var accessory: some View {
        if let state = states.first {
            let item = HoneyJarPresentation(ProviderDashboardPresentation(provider: state.provider, state: state, at: date))
            let value = item.dashboard
            let name = ProviderPresentation.name(state.provider)
            let symbol = ProviderPresentation.symbol(state.provider)
            if let window = value.summaryWindow {
                let slot = window.id == item.fiveHour?.id ? "5 小时" : window.id == item.weekly?.id ? "本周" : window.shortLabel
                if family == .accessoryCircular {
                    Gauge(value: window.fraction, in: 0...1) { Image(systemName: symbol) } currentValueLabel: {
                        VStack(spacing: 0) {
                            Image(systemName: symbol).font(.system(size: 9))
                            Text(String(Int(window.remaining.rounded()))).font(.system(size: 15, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.5).lineLimit(1)
                        }
                    }.gaugeStyle(.accessoryCircularCapacity).widgetAccentable().privacySensitive()
                } else if family == .accessoryInline {
                    Text(name + " " + ProviderPresentation.percent(window.remaining) + (refillText(window).map { " · " + $0 } ?? ""))
                        .privacySensitive().contentTransition(.numericText())
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Gauge(value: window.fraction, in: 0...1) { Text(name + " " + slot).font(.caption.bold()) } currentValueLabel: {
                            Text(ProviderPresentation.percent(window.remaining)).monospacedDigit()
                        }.gaugeStyle(.accessoryLinearCapacity).widgetAccentable()
                        if let reset = window.window.resetsAt, reset > date, window.remaining < 100 {
                            Text("回满 " + ResetCountdown.compact(reset.timeIntervalSince(date))).font(.caption2).monospacedDigit()
                        } else { Text(value.status).font(.caption2) }
                    }.privacySensitive()
                }
            } else {
                balanceAccessory(value, name: name, symbol: symbol)
            }
        } else { Text("打开轻松熊连接账户") }
    }

    /// 「2天后回满」；已满或没有重置时间返回 nil。
    private func refillText(_ window: UsageWindowPresentation) -> String? {
        guard let reset = window.window.resetsAt, reset > date, window.remaining < 100 else { return nil }
        return coarseSpan(reset.timeIntervalSince(date)) + "后回满"
    }

    @ViewBuilder private func balanceAccessory(_ value: ProviderDashboardPresentation, name: String, symbol: String) -> some View {
        if family == .accessoryCircular {
            VStack(spacing: 1) {
                Image(systemName: symbol).widgetAccentable()
                Text(value.balances.first.map { NSDecimalNumber(decimal: $0.balance.total).stringValue } ?? "—")
                    .font(.caption2.bold()).minimumScaleFactor(0.4).lineLimit(1)
            }.privacySensitive()
        } else if family == .accessoryInline {
            Text(name + " · " + value.headline).privacySensitive().contentTransition(.numericText())
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.caption.bold())
                Text(value.headline).font(.system(.headline, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                Text(value.status).font(.caption2)
            }.privacySensitive()
        }
    }
}
