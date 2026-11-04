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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var monochrome: Bool { renderingMode != .fullColor }
    private var secondary: Color { monochrome ? .primary.opacity(0.72) : BearTheme.secondaryText(scheme) }
    private var track: Color? { monochrome ? .primary.opacity(0.18) : nil }
    private var compact: Bool { family == .systemSmall || (provider == nil && family == .systemMedium) }
    var body: some View {
        VStack(alignment: .leading, spacing: provider == nil && family == .systemLarge ? 12 : 8) {
            HStack {
                Text(provider.map(ProviderPresentation.name) ?? "AI 额度").font(.subheadline.bold())
                Spacer(minLength: 0)
                Image(systemName: "chart.bar.xaxis").font(.caption).foregroundStyle(BearTheme.accent(scheme))
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
            if family == .systemLarge { Spacer(minLength: 0) }
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
                HStack(spacing: 7) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("剩余").font(.caption2).foregroundStyle(secondary)
                        Text(ProviderPresentation.percent(window.remaining))
                            .font(.system(provider == nil ? .headline : .title2, design: .rounded).bold())
                            .monospacedDigit().minimumScaleFactor(0.7).lineLimit(1).contentTransition(.numericText()).id(window.id)
                    }
                    if provider != nil {
                        BearQuotaArc(fraction: window.fraction, color: quotaColor(window, value.provider), stale: value.isStale, trackColor: track).widgetAccentable()
                            .frame(width: 35, height: 35)
                    }
                }
                BearCapacityBar(fraction: window.fraction, color: quotaColor(window, value.provider), stale: value.isStale, trackColor: track).widgetAccentable()
                Text(window.shortLabel).font(.caption2).foregroundStyle(secondary).lineLimit(1)
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
                } else if let balance = value.balances.first, let parts = balance.parts {
                    BearCompositionBar(fractions: parts.map(\.fraction), color: series(value.provider)).widgetAccentable()
                    HStack {
                        Text("赠送 " + ProviderPresentation.money(parts[0].amount, currency: balance.balance.currency))
                        Spacer(minLength: 3)
                        Text("充值 " + ProviderPresentation.money(parts[1].amount, currency: balance.balance.currency))
                    }.font(.caption2).foregroundStyle(secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
    }
    private func timestamp(_ value: ProviderDashboardPresentation) -> some View {
        HStack(spacing: 3) {
            if value.isStale && value.state?.snapshot != nil {
                Image(systemName: "clock.badge.exclamationmark").accessibilityHidden(true)
            }
            Text(value.status == "已同步" ? "更新于" : value.status)
            if let snapshot = value.state?.snapshot { Text(snapshot.fetchedAt, style: .time) }
        }.font(.caption2).foregroundStyle(secondary).lineLimit(2)
    }
    private func series(_ provider: ProviderID) -> Color { monochrome ? .primary : BearTheme.series(ProviderPresentation.paletteIndex(provider), scheme) }
    private func quotaColor(_ window: UsageWindowPresentation, _ provider: ProviderID) -> Color {
        monochrome ? .primary : BearTheme.quotaColor(window.remaining, series: ProviderPresentation.paletteIndex(provider), scheme: scheme)
    }
}
