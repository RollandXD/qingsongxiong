import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import SwiftUI

/// 恢复预览的读数：拖动时间尺时告诉用户“到那一刻会回满多少”，不覆盖主卡的当前读数。
/// 只展示已连接的厂商窗口；中转没有重置周期，不参与预测。
struct RecoveryPreviewRows: View {
    let model: AIUsageModel
    let now: Date
    let offset: TimeInterval

    @Environment(\.colorScheme) private var scheme

    private var providers: [ProviderID] {
        ProviderID.allCases.filter { model.states[$0]?.connection == .connected }
    }

    var body: some View {
        if providers.isEmpty {
            Text("连接账户后可以预览回满时间。")
                .font(.footnote)
                .foregroundStyle(BearTheme.secondaryText(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("recovery-empty")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(providers, id: \.self) { provider in
                    ForEach(windows(for: provider), id: \.id) { window in
                        row(provider: provider, window: window)
                    }
                }
            }
        }
    }

    private func windows(for provider: ProviderID) -> [UsageWindowPresentation] {
        guard let state = model.states[provider], state.connection == .connected else { return [] }
        return ProviderDashboardPresentation(provider: provider, state: state, at: now).windows
    }

    private func row(provider: ProviderID, window: UsageWindowPresentation) -> some View {
        let target = now.addingTimeInterval(offset)
        let resetsAt = window.window.resetsAt
        let refilled = resetsAt.map { $0 <= target } ?? false
        let remaining = refilled ? 100.0 : window.remaining
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(BearTheme.series(ProviderPresentation.paletteIndex(provider), scheme))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(ProviderPresentation.name(provider) + " · " + window.label)
                .font(.footnote)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(ProviderPresentation.percent(remaining))
                .font(.system(.footnote, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(refilled ? "已回满" : "回满于 " + (resetsAt.map { Self.time($0, at: target) } ?? "未知"))
                .font(.caption2)
                .foregroundStyle(BearTheme.secondaryText(scheme))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recovery-" + provider.rawValue + "-" + window.id)
    }

    /// 已回满时说明“何时”，未回满时说明“还剩多久”，两种说法都不假装是精确预测。
    static func time(_ date: Date, at reference: Date) -> String {
        let delta = date.timeIntervalSince(reference)
        if delta <= 0 { return "已过" }
        let minutes = Int((delta / 60).rounded())
        if minutes < 60 { return "\(minutes) 分钟后" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) 小时后" : "\(hours) 小时 \(rest) 分后"
    }
}
