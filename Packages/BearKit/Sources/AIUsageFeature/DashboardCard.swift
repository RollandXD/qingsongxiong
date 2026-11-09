import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

struct ProviderIdentity: View {
    let presentation: ProviderDashboardPresentation
    var refreshing = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: ProviderPresentation.symbol(presentation.provider))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BearTheme.series(ProviderPresentation.paletteIndex(presentation.provider), scheme))
            Text(ProviderPresentation.name(presentation.provider)).font(.headline)
            Spacer(minLength: 4)
            if refreshing { ProgressView().controlSize(.small).accessibilityLabel("正在刷新") }
            else {
                HStack(spacing: 4) {
                    if presentation.isStale && presentation.state?.snapshot != nil {
                        Image(systemName: "clock.badge.exclamationmark").accessibilityHidden(true)
                    }
                    Text(presentation.status)
                }.font(.caption.weight(.medium))
                    .foregroundStyle(presentation.isStale && presentation.state?.snapshot != nil ? BearTheme.warning(scheme) : BearTheme.secondaryText(scheme))
            }
        }.foregroundStyle(BearTheme.text(scheme))
    }
}

struct DashboardMetric: View {
    let presentation: ProviderDashboardPresentation
    let focused: UsageWindowPresentation?
    var large = false
    @ScaledMetric(relativeTo: .largeTitle) private var metricSize = 38
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let balance = presentation.balances.first {
                Text(balance.balance.currency + " 余额").font(.caption.weight(.medium)).foregroundStyle(BearTheme.secondaryText(scheme))
                Text(NSDecimalNumber(decimal: balance.balance.total).stringValue)
                    .font(.system(size: metricSize * (large ? 1.3 : 1), weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.55)
                    .accessibilityLabel("可用余额，" + balance.balance.currency + " " + NSDecimalNumber(decimal: balance.balance.total).stringValue)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: NSDecimalNumber(decimal: balance.balance.total).doubleValue)).id(balance.id)
                if presentation.balances.count > 1 {
                    Text("另有 \(presentation.balances.count - 1) 种币种").font(.caption).foregroundStyle(BearTheme.secondaryText(scheme))
                } else { Text("官方 API 可用余额").font(.caption).foregroundStyle(BearTheme.secondaryText(scheme)) }
            } else if let window = focused ?? presentation.summaryWindow {
                Text("剩余").font(.caption.weight(.medium)).foregroundStyle(BearTheme.secondaryText(scheme))
                Text(ProviderPresentation.percent(window.remaining))
                    .font(.system(size: metricSize * (large ? 1.3 : 1), weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: window.remaining)).id(window.id)
                Text(window.label).font(.footnote.weight(.medium)).foregroundStyle(BearTheme.secondaryText(scheme))
                    .lineLimit(2)
            } else {
                Text("—").font(.system(size: metricSize, weight: .semibold, design: .rounded))
                    .accessibilityHidden(true) // 下方状态文字已经说明未连接；破折号只是装饰。
                Text(presentation.status).font(.subheadline).foregroundStyle(BearTheme.secondaryText(scheme))
            }
        }.foregroundStyle(BearTheme.text(scheme)).frame(maxWidth: .infinity, alignment: .leading)
            .id(presentation.state?.sessionID)
    }
}

private struct MeterGeometry: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    @ViewBuilder func body(content: Content) -> some View {
        if let namespace { content.matchedGeometryEffect(id: id, in: namespace) }
        else { content }
    }
}

struct WindowMeter: View {
    let window: UsageWindowPresentation
    let provider: ProviderID
    let stale: Bool
    var namespace: Namespace.ID?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        BearTickCapsule(fraction: window.fraction,
                        color: BearTheme.quotaColor(window.remaining, series: ProviderPresentation.paletteIndex(provider), scheme: scheme), stale: stale)
            .modifier(MeterGeometry(id: provider.rawValue + "." + window.id, namespace: namespace))
    }
}

struct UsageWindowRow: View {
    let window: UsageWindowPresentation
    let provider: ProviderID
    let stale: Bool
    var selected = false
    var namespace: Namespace.ID?
    var onSelect: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var body: some View {
        if let onSelect {
            Button(action: onSelect) { row }
                .buttonStyle(BearPressStyle())
                .accessibilityIdentifier("window-" + provider.rawValue + "-" + window.id)
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else { row.accessibilityElement(children: .combine) }
    }
    private var row: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(window.label).font(.subheadline.weight(.semibold))
                    Text(window.role.label).font(.caption2).foregroundStyle(BearTheme.secondaryText(scheme))
                }
                Spacer(minLength: 3)
                Text(ProviderPresentation.percent(window.remaining)).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(BearTheme.accent(scheme)) }
            }
            WindowMeter(window: window, provider: provider, stale: stale, namespace: namespace)
            HStack(alignment: .firstTextBaseline) {
                Text("已用 " + ProviderPresentation.percent(window.window.usedPercent))
                Spacer(minLength: 4)
                if let reset = window.window.resetsAt, reset > Date() {
                    HStack(spacing: 3) {
                        Text("重置倒计时")
                        Text(timerInterval: Date()...reset, countsDown: true)
                            .monospacedDigit().multilineTextAlignment(.trailing).frame(maxWidth: 110)
                    }
                } else {
                    Text(resetLabel).multilineTextAlignment(.trailing)
                }
            }.font(.caption2).foregroundStyle(BearTheme.secondaryText(scheme))
        }
        .foregroundStyle(BearTheme.text(scheme))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? BearTheme.accent(scheme).opacity(scheme == .dark ? 0.14 : 0.08) : .clear, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .contentShape(Rectangle())
    }
    private var resetLabel: String {
        window.resetLabel(at: Date())
    }
}

struct BalanceBreakdown: View {
    let balance: BalancePresentation
    let color: Color
    var namespace: Namespace.ID?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let parts = balance.parts {
                BearCompositionBar(fractions: parts.map(\.fraction), color: color)
                    .modifier(MeterGeometry(id: "balance." + balance.id, namespace: namespace))
            }
            LabeledContent {
                Text(balance.balance.granted.map { ProviderPresentation.money($0, currency: balance.balance.currency) } ?? "未提供")
            } label: {
                Label { Text("赠送余额") } icon: { Circle().fill(color).frame(width: 8, height: 8) }
            }
            LabeledContent {
                Text(balance.balance.toppedUp.map { ProviderPresentation.money($0, currency: balance.balance.currency) } ?? "未提供")
            } label: {
                Label { Text("充值余额") } icon: {
                    Circle().fill(color.opacity(scheme == .dark ? 0.45 : 0.25)).frame(width: 8, height: 8)
                }
            }
            if balance.parts == nil {
                Text(balance.balance.total == 0 ? "余额为零" : "当前数据不适合绘制组成比例")
                    .font(.caption).foregroundStyle(BearTheme.secondaryText(scheme))
            }
        }.font(.subheadline).foregroundStyle(BearTheme.text(scheme))
    }
}

struct DashboardProviderCard: View {
    let presentation: ProviderDashboardPresentation
    let expanded: Bool
    let focusedID: String?
    let refreshing: Bool
    let feedback: String?
    let navigationNamespace: Namespace.ID
    let onNavigate: () -> Void
    let onToggle: () -> Void
    let onFocus: @MainActor @Sendable (String) -> Void
    @Namespace private var meterNamespace
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var provider: ProviderID { presentation.provider }
    private var focused: UsageWindowPresentation? {
        presentation.windows.first { $0.id == focusedID } ?? presentation.summaryWindow
    }
    private var series: Color { BearTheme.series(ProviderPresentation.paletteIndex(provider), scheme) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: provider) {
                VStack(alignment: .leading, spacing: 12) {
                    ProviderIdentity(presentation: presentation, refreshing: refreshing)
                    HStack(alignment: .center, spacing: 16) {
                        DashboardMetric(presentation: presentation, focused: expanded ? focused : nil)
                        compactGraphic.frame(width: expanded ? 70 : 106)
                    }.frame(minHeight: 78)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BearLiftPressStyle())
            .simultaneousGesture(TapGesture().onEnded { _ in onNavigate() })
            .accessibilityIdentifier("provider-" + provider.rawValue)
            HStack(alignment: .center) {
                Text(footer).font(.caption2).foregroundStyle(BearTheme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(BearVerifiedFlash(trigger: feedback))
                Spacer(minLength: 4)
                if !presentation.windows.isEmpty || !presentation.balances.isEmpty {
                    Button(action: onToggle) {
                        HStack(spacing: 5) {
                            Text(expanded ? "收起" : provider == .deepseek ? "组成" : "窗口")
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2.weight(.bold))
                        }.font(.caption.weight(.semibold)).padding(.horizontal, 3)
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("expand-" + provider.rawValue)
                }
            }
            if expanded { expandedContent.transition(.opacity.combined(with: .offset(y: -6))) }
        }
        .padding(18)
        .padding(.leading, 4)
        .overlay(alignment: .leading) {
            Capsule().fill(series.gradient).frame(width: 4).padding(.vertical, 22).padding(.leading, 8)
                .accessibilityHidden(true)
        }
        .bearGlassCard(tint: series, cornerRadius: 26)
        .matchedTransitionSource(id: provider, in: navigationNamespace)
        .animation(reduceMotion ? BearMotion.quiet : BearMotion.unfold, value: expanded)
        .sensoryFeedback(.selection, trigger: focusedID)
    }
    private var footer: String {
        if let feedback { return feedback }
        guard let snapshot = presentation.state?.snapshot else { return presentation.connectionHint }
        return (presentation.isStale ? "旧读数 " : "更新于 ") + snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
    }
    @ViewBuilder private var compactGraphic: some View {
        if provider == .deepseek, let balance = presentation.balances.first {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "wallet.bifold").font(.title2).foregroundStyle(series)
                if !expanded, let parts = balance.parts {
                    BearCompositionBar(fractions: parts.map(\.fraction), color: series)
                        .matchedGeometryEffect(id: "balance." + balance.id, in: meterNamespace)
                    Text("赠送 / 充值").font(.caption2).foregroundStyle(BearTheme.secondaryText(scheme))
                } else { Text("独立 API 余额").font(.caption2).foregroundStyle(BearTheme.secondaryText(scheme)) }
            }
        } else if expanded, let focused {
            BearRing(fraction: focused.fraction,
                     color: BearTheme.quotaColor(focused.remaining, series: ProviderPresentation.paletteIndex(provider), scheme: scheme),
                     stale: presentation.isStale).frame(height: 68)
        } else if !presentation.windows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(presentation.compactWindows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.shortLabel)
                            Spacer(minLength: 2)
                            Text(ProviderPresentation.percent(window.remaining)).monospacedDigit()
                        }.font(.caption2).foregroundStyle(BearTheme.secondaryText(scheme))
                        WindowMeter(window: window, provider: provider, stale: presentation.isStale, namespace: meterNamespace)
                    }
                }
            }
        } else {
            Image(systemName: "arrow.up.right").font(.title2).foregroundStyle(series).frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder private var expandedContent: some View {
        if !presentation.windows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if presentation.windows.count > 1 {
                    Picker("选择额度窗口", selection: Binding(get: { focused?.id ?? "" }, set: onFocus)) {
                        ForEach(presentation.windows) { Text($0.shortLabel).tag($0.id) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("window-picker-" + provider.rawValue)
                        .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height),
                                  let current = presentation.windows.firstIndex(where: { $0.id == focused?.id }) else { return }
                            let index = min(presentation.windows.count - 1, max(0, current + (value.translation.width < 0 ? 1 : -1)))
                            onFocus(presentation.windows[index].id)
                        })
                }
                ForEach(Array(presentation.windows.enumerated()), id: \.element.id) { index, window in
                    UsageWindowRow(window: window, provider: provider, stale: presentation.isStale,
                                   selected: focused?.id == window.id, namespace: meterNamespace,
                                   onSelect: { onFocus(window.id) })
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .animation(BearMotion.choose(BearMotion.unfold, reduceMotion: reduceMotion)
                            .delay(reduceMotion ? 0 : Double(index) * BearMotion.rowStagger), value: expanded)
                }
                Text("各窗口独立计算，比例不能相加。").font(.caption2).foregroundStyle(BearTheme.secondaryText(scheme)).padding(.horizontal, 12)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(presentation.balances) { balance in
                    if presentation.balances.count > 1 { Text(balance.balance.currency).font(.headline) }
                    BalanceBreakdown(balance: balance, color: series, namespace: meterNamespace)
                }
            }.padding(.top, 4)
        }
    }
}
