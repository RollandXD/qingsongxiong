import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI
import WidgetKit

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
    private var track: Color? { monochrome ? .primary.opacity(0.18) : nil }
    private var compact: Bool { family == .systemSmall || (provider == nil && family == .systemMedium) }
    var body: some View {
        Group {
            if [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family) { accessory }
            else { panel }
        }
    }
    private var panel: some View {
        VStack(alignment: .leading, spacing: provider == nil && family == .systemLarge ? 12 : 8) {
            HStack {
                Text(provider.map(ProviderPresentation.name) ?? "AI 额度").font(.subheadline.bold())
                Spacer(minLength: 0)
                if let refreshControl { refreshControl }
                else { Image(systemName: "chart.bar.xaxis").font(.caption).foregroundStyle(BearTheme.accent(scheme)) }
            }
            if provider == nil && family == .systemMedium {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(states, id: \.provider) { state in
                        metricLink(state).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            } else {
                ForEach(states, id: \.provider) { state in metricLink(state) }
            }
            if family == .systemLarge {
                ForEach(relays.prefix(2)) { state in
                    Link(destination: RelayPresentation.url(state.id)) {
                        HStack {
                            Label(state.account.displayName, systemImage: "network")
                            Spacer(minLength: 4)
                            Text(RelayPresentation(state: state, at: date).headline).monospacedDigit().privacySensitive()
                        }.font(.caption).foregroundStyle(secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(BearTheme.text(scheme))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func metricLink(_ state: ProviderState) -> some View {
        Link(destination: URL(string: "qingsongxiong://ai-usage/provider/" + state.provider.rawValue)!) {
            metric(ProviderDashboardPresentation(provider: state.provider, state: state, at: date))
                .id(state.sessionID)
        }
        .privacySensitive().accessibilityElement(children: .combine)
    }
    @ViewBuilder private func metric(_ value: ProviderDashboardPresentation) -> some View {
        if compact { compactMetric(value) }
        else { wideMetric(value) }
    }
    private func compactMetric(_ value: ProviderDashboardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if provider == nil {
                Text(ProviderPresentation.name(value.provider)).font(.caption2.bold())
            }
            if let window = value.summaryWindow {
                ZStack {
                    BearQuotaArc(fraction: window.fraction, color: quotaColor(window, value.provider), stale: value.isStale, trackColor: track)
                        .widgetAccentable()
                    VStack(spacing: 1) {
                        if provider != nil { Text("剩余").font(.caption2).foregroundStyle(secondary) }
                        Text(ProviderPresentation.percent(window.remaining))
                            .font(.system(provider == nil ? .headline : .title2, design: .rounded).bold())
                            .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1).contentTransition(.numericText()).id(window.id)
                    }.padding(8)
                }.frame(width: provider == nil ? 48 : 64, height: provider == nil ? 48 : 64)
                if provider == nil { Text(window.shortLabel).font(.caption2).foregroundStyle(secondary).lineLimit(1) }
                else { resetLabel(window) }
            } else if let balance = value.balances.first {
                Text(balance.balance.currency).font(.caption2).foregroundStyle(secondary)
                Text(NSDecimalNumber(decimal: balance.balance.total).stringValue)
                    .font(.system(provider == nil ? .headline : .title2, design: .rounded).bold())
                    .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1).contentTransition(.numericText()).id(balance.id)
                if let parts = balance.parts {
                    BearCompositionBar(fractions: parts.map(\.fraction), color: series(value.provider)).widgetAccentable()
                }
            } else { Text("—").font(.system(.title2, design: .rounded)).foregroundStyle(secondary) }
            timestamp(value)
        }
    }
    private func wideMetric(_ value: ProviderDashboardPresentation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 14) {
                if let window = value.summaryWindow {
                    BearQuotaArc(fraction: window.fraction, color: quotaColor(window, value.provider), stale: value.isStale, trackColor: track).widgetAccentable()
                        .frame(width: family == .systemLarge ? 48 : 60, height: family == .systemLarge ? 48 : 60)
                } else if !value.balances.isEmpty {
                    Image(systemName: "wallet.bifold").font(.title2).foregroundStyle(series(value.provider))
                        .frame(width: family == .systemLarge ? 48 : 60, height: family == .systemLarge ? 48 : 60)
                        .widgetAccentable().accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if provider == nil { Text(ProviderPresentation.name(value.provider)).font(.subheadline.bold()) }
                    Text(value.headline).font(.system(.title3, design: .rounded).bold())
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65).contentTransition(.numericText())
                        .id(value.summaryWindow?.id ?? value.balances.first?.id ?? "empty")
                    if let window = value.summaryWindow {
                        Text(window.label).font(.caption2).foregroundStyle(secondary).lineLimit(1)
                    }
                    timestamp(value)
                }
                Spacer(minLength: 0)
            }
            if provider != nil {
                if value.windows.count > 1 {
                    ForEach(value.compactWindows) { window in
                        HStack(spacing: 8) {
                            Text(window.shortLabel).font(.caption2).frame(width: 42, alignment: .leading)
                            BearCapacityBar(fraction: window.fraction, color: quotaColor(window, value.provider), stale: value.isStale, trackColor: track).widgetAccentable()
                            Text(ProviderPresentation.percent(window.remaining)).font(.caption2.monospacedDigit()).frame(width: 40, alignment: .trailing)
                        }.foregroundStyle(secondary)
                    }
                }
            }
            if let balance = value.balances.first, let parts = balance.parts {
                BearCompositionBar(fractions: parts.map(\.fraction), color: series(value.provider)).widgetAccentable()
                HStack {
                    Text("赠送 " + ProviderPresentation.money(parts[0].amount, currency: balance.balance.currency))
                    Spacer(minLength: 3)
                    Text("充值 " + ProviderPresentation.money(parts[1].amount, currency: balance.balance.currency))
                }.font(.caption2).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
    @ViewBuilder private var accessory: some View {
        if let state = states.first {
            let value = ProviderDashboardPresentation(provider: state.provider, state: state, at: date)
            if family == .accessoryCircular, let window = value.summaryWindow {
                Gauge(value: window.fraction, in: 0...1) { Text(ProviderPresentation.name(state.provider)) } currentValueLabel: {
                    Text(ProviderPresentation.percent(window.remaining)).minimumScaleFactor(0.5)
                }.gaugeStyle(.accessoryCircularCapacity).widgetAccentable().privacySensitive()
            } else if family == .accessoryInline {
                Text(ProviderPresentation.name(state.provider) + " · " + value.headline).privacySensitive().contentTransition(.numericText())
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ProviderPresentation.name(state.provider)).font(.caption.bold())
                    Text(value.headline).font(.headline).monospacedDigit().contentTransition(.numericText())
                    if let window = value.summaryWindow { resetLabel(window) }
                    else { Text(value.status).font(.caption2) }
                }.privacySensitive()
            }
        } else { Text("打开轻松熊连接账户") }
    }
    @ViewBuilder private func resetLabel(_ window: UsageWindowPresentation) -> some View {
        if let reset = window.window.resetsAt, reset > date {
            HStack(spacing: 2) { Text(reset, style: .relative); Text("重置") }.font(.caption2).foregroundStyle(secondary).lineLimit(1)
        }
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
    private func series(_ provider: ProviderID) -> Color { monochrome ? .primary : BearTheme.series(ProviderPresentation.paletteIndex(provider), scheme) }
    private func quotaColor(_ window: UsageWindowPresentation, _ provider: ProviderID) -> Color {
        monochrome ? .primary : BearTheme.quotaColor(window.remaining, series: ProviderPresentation.paletteIndex(provider), scheme: scheme)
    }
}
