import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

extension DashboardOverviewPresentation.Mood {
    var bear: BearMood {
        switch self { case .calm: .calm; case .watchful: .watchful; case .urgent: .urgent; case .asleep: .asleep }
    }
}

/// 首页顶部「今日状态」：大号剩余数字 + 三家同心星环 + 情绪熊 + 一句话摘要。
struct DashboardHero: View {
    let overview: DashboardOverviewPresentation
    let entered: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = 64
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lanes: [BearOrbit.Lane] {
        overview.providers.filter { !$0.windows.isEmpty || $0.state?.connection != .connected }
            .filter { $0.provider != .deepseek }
            .map { value in
            let fraction = value.summaryWindow?.fraction ?? 0
            return BearOrbit.Lane(id: value.provider.rawValue, fraction: entered ? fraction : 0,
                color: BearTheme.quotaColor(value.summaryWindow?.remaining ?? 100,
                    series: ProviderPresentation.paletteIndex(value.provider), scheme: scheme),
                stale: value.isStale)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    BearMoodMark(mood: overview.mood.bear).frame(width: 30, height: 30)
                    Text(overview.moodLabel).font(.subheadline.weight(.semibold))
                        .foregroundStyle(moodColor)
                        .contentTransition(.opacity)
                }
                if let tightest = overview.tightest {
                    Text(entered ? ProviderPresentation.percent(tightest.window.remaining) : "0%")
                        .font(.system(size: heroSize, weight: .bold, design: .rounded))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText(countsDown: true))
                        .foregroundStyle(BearTheme.text(scheme))
                } else {
                    Text("—").font(.system(size: heroSize, weight: .bold, design: .rounded))
                        .foregroundStyle(BearTheme.secondaryText(scheme))
                }
                Text(overview.summary(at: Date()))
                    .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
                .frame(maxWidth: .infinity, alignment: .leading)
            if !lanes.isEmpty {
                VStack(spacing: 10) {
                    BearOrbit(lanes: lanes, lineWidth: 9, gap: 4)
                        .frame(width: 104, height: 104)
                        .animation(reduceMotion ? BearMotion.quiet : BearMotion.entrance, value: lanes)
                    ForEach(lanes) { lane in
                        HStack(spacing: 5) {
                            Circle().fill(lane.color).frame(width: 5, height: 5)
                            Text(lane.id == ProviderID.codex.rawValue ? "Codex" : "Claude")
                                .foregroundStyle(BearTheme.secondaryText(scheme))
                        }.font(.caption2)
                    }
                }.accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .bearGlassCard(tint: BearTheme.accent(scheme), cornerRadius: 30)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(overview.moodLabel + "，" + overview.summary(at: Date()))
            .accessibilityIdentifier("dashboard-hero")
    }

    private var moodColor: Color {
        switch overview.mood {
            case .calm: BearTheme.success(scheme)
            case .watchful: BearTheme.warning(scheme)
            case .urgent: BearTheme.danger(scheme)
            case .asleep: BearTheme.secondaryText(scheme)
        }
    }
}
