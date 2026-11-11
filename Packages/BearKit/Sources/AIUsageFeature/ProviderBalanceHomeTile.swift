import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

/// 官方 API 余额主卡。金额、币种与新鲜度同级可见；不画不存在的百分比/重置线。
struct ProviderBalanceHomeTile: View {
    let presentation: ProviderDashboardPresentation
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(BearTheme.series(ProviderPresentation.paletteIndex(presentation.provider), scheme))
                    .frame(width: 8, height: 8)
                Text(ProviderPresentation.name(presentation.provider))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BearTheme.text(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(BearTheme.secondaryText(scheme))
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                if presentation.balances.isEmpty {
                    Text("暂无余额读数")
                        .font(.headline)
                        .foregroundStyle(BearTheme.secondaryText(scheme))
                } else {
                    ForEach(presentation.balances) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.balance.currency)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BearTheme.secondaryText(scheme))
                            Text(NSDecimalNumber(decimal: item.balance.total).stringValue)
                                .font(.system(size: presentation.balances.count > 1 ? 26 : 32,
                                              weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .foregroundStyle(BearTheme.text(scheme))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("官方 API 余额")
                    .font(.caption)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 12)
            Label(presentation.status, systemImage: presentation.isStale ? "clock.badge.exclamationmark" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(presentation.isStale ? BearTheme.warning(scheme) : BearTheme.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        .contentShape(.rect)
    }
}
