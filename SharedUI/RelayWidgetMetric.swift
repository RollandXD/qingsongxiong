import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import SwiftUI
import WidgetKit

struct RelayWidgetMetric: View {
    let state: RelayState?
    let date: Date
    let family: WidgetFamily
    var refreshControl: AnyView?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
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
                } else {
                    VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 3 : 10) {
                        HStack {
                            Text(state.account.displayName).font(.subheadline.bold()).lineLimit(1)
                            Spacer(minLength: 0)
                            if family != .accessoryRectangular { refreshControl }
                        }
                        Text(presentation.headline).font(.system(family == .accessoryRectangular ? .headline : .title, design: .rounded).bold())
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).contentTransition(.numericText())
                            .accessibilityLabel(presentation.fullValue)
                        Text(presentation.status).font(.caption2).foregroundStyle(.secondary)
                        if family != .accessoryRectangular, let snapshot = state.snapshot {
                            HStack(spacing: 3) { Text("更新于"); Text(snapshot.fetchedAt, style: .time) }.font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Label("中转账户", systemImage: "network")
                    Text("账户已移除或需打开 App").font(.caption)
                }
            }
        }.privacySensitive().foregroundStyle(renderingMode == .fullColor ? BearTheme.text(scheme) : Color.primary)
    }
}
