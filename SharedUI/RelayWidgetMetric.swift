import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import SwiftUI
import WidgetKit

extension RelayPresentation {
    /// 把「USD 12.34」拆成币种码、金额与币种符号，供币卡排版；没有读数时为 nil。
    var widgetParts: (code: String, amount: String, symbol: String)? {
        guard let balance = state.snapshot?.balances.first else { return nil }
        let prefix = balance.currency + " "
        let amount = headline.hasPrefix(prefix) ? String(headline.dropFirst(prefix.count)) : headline
        let symbol: String
        switch balance.currency.uppercased() {
        case "USD": symbol = "$"
        case "CNY": symbol = "¥"
        case "EUR": symbol = "€"
        default: symbol = String(balance.currency.prefix(1))
        }
        return (code: balance.currency, amount: amount, symbol: symbol)
    }
}

/// 中转账户：一张币卡，金额用圆体大字，读数变化走 numericText 过渡。
struct RelayWidgetMetric: View {
    let state: RelayState?
    let date: Date
    let family: WidgetFamily
    var refreshControl: AnyView?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var monochrome: Bool { renderingMode != .fullColor }
    private var ink: Color { monochrome ? .primary : BearTheme.text(scheme) }
    private var secondary: Color { monochrome ? .primary.opacity(0.72) : BearTheme.secondaryText(scheme) }
    private var presentation: RelayPresentation? { state.map { RelayPresentation(state: $0, at: date) } }
    var body: some View {
        Group {
            if let state, let presentation {
                if family == .accessoryInline {
                    Text(state.account.displayName + " · " + presentation.headline).contentTransition(.numericText())
                } else if family == .accessoryCircular {
                    VStack(spacing: 2) {
                        Image(systemName: "wallet.bifold").widgetAccentable()
                        Text(presentation.headline).font(.caption2.bold()).minimumScaleFactor(0.4).lineLimit(1)
                    }
                } else if family == .accessoryRectangular {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.account.displayName).font(.subheadline.bold()).lineLimit(1)
                        Text(presentation.headline).font(.system(.headline, design: .rounded).bold())
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText())
                            .accessibilityLabel(presentation.fullValue)
                        Text(presentation.status).font(.caption2)
                    }
                } else {
                    coinCard(state, presentation)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Label("中转账户", systemImage: "network")
                    Text("账户已移除或需打开 App").font(.caption)
                }
            }
        }.privacySensitive().foregroundStyle(ink)
    }

    private func coinCard(_ state: RelayState, _ presentation: RelayPresentation) -> some View {
        let parts = presentation.widgetParts
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(monochrome ? Color.primary : BearTheme.relay(scheme)).frame(width: 8, height: 8)
                    .widgetAccentable().accessibilityHidden(true)
                Text(state.account.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(ink).lineLimit(1)
                Spacer(minLength: 4)
                if let refreshControl { refreshControl }
            }.frame(height: 24)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                coin(parts?.symbol ?? "¤")
                Text(parts?.code ?? "余额").font(.caption.weight(.semibold)).foregroundStyle(secondary)
            }
            Text(parts?.amount ?? "—")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText())
                .foregroundStyle(ink)
                .accessibilityLabel(presentation.fullValue)
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.status)
                if let snapshot = state.snapshot {
                    HStack(spacing: 3) { Text("更新于"); Text(snapshot.fetchedAt, style: .time) }
                }
            }.font(.caption2).foregroundStyle(secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func coin(_ symbol: String) -> some View {
        ZStack {
            Circle().fill(monochrome ? Color.primary.opacity(0.14) : BearTheme.relay(scheme).opacity(0.22))
            Circle().strokeBorder(monochrome ? Color.primary : BearTheme.relay(scheme), lineWidth: 2)
            Text(symbol).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(ink)
        }
        .frame(width: 26, height: 26)
        .widgetAccentable()
        .accessibilityHidden(true)
    }
}
