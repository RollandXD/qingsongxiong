import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import SwiftUI

/// 时间顺序而非用量排名；仅显示服务端实际提供的重置时刻。
struct WindowResetTimeline: View {
    let presentation: ProviderDashboardPresentation
    @Environment(\.colorScheme) private var scheme
    private var series: Color { BearTheme.series(ProviderPresentation.paletteIndex(presentation.provider), scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("接下来的重置").font(.footnote.weight(.semibold)).foregroundStyle(BearTheme.secondaryText(scheme))
                .padding(.horizontal, 16).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(presentation.resetTimeline.enumerated()), id: \.element.id) { index, window in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 5) {
                            Circle().fill(series).frame(width: 7, height: 7).padding(.top, 6)
                            if index < presentation.resetTimeline.count - 1 {
                                Rectangle().fill(series.opacity(0.18)).frame(width: 1).frame(minHeight: 44)
                            }
                        }.frame(width: 12).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(window.label).font(.subheadline.weight(.semibold))
                            if let reset = window.window.resetsAt {
                                Text(reset, format: .dateTime.month().day().hour().minute())
                                    .font(.caption).foregroundStyle(BearTheme.secondaryText(scheme))
                                if reset > Date() {
                                    HStack(spacing: 4) {
                                        Text("距重置")
                                        Text(timerInterval: Date()...reset, countsDown: true)
                                            .monospacedDigit().multilineTextAlignment(.leading)
                                    }.font(.caption).foregroundStyle(BearTheme.secondaryText(scheme))
                                } else {
                                    Text("时间已过，等待服务端确认").font(.caption).foregroundStyle(BearTheme.warning(scheme))
                                }
                            }
                        }.padding(.bottom, index == presentation.resetTimeline.count - 1 ? 0 : 20)
                    }.accessibilityElement(children: .combine)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .padding(16).background(BearTheme.surface(scheme), in: .rect(cornerRadius: 26, style: .continuous))
        }.foregroundStyle(BearTheme.text(scheme)).accessibilityIdentifier("reset-timeline")
    }
}
