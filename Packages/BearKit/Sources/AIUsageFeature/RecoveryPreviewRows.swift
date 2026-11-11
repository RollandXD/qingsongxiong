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

    /// 一行一个窗口：左侧名称、右侧百分比，回满时间单独一行。
    ///
    /// 名字和倒计时都真实存在长文本（“Codex · 7 天”“回满于 48 小时后”），
    /// 挤在同一行会被原生审计判为裁切，所以上下分行并允许缩放。
    private func row(provider: ProviderID, window: UsageWindowPresentation) -> some View {
        let target = now.addingTimeInterval(offset)
        let resetsAt = window.window.resetsAt
        let dashboard = ProviderDashboardPresentation(provider: provider, state: model.states[provider], at: now)
        let canPreview = !dashboard.isStale && dashboard.state?.failure == nil
            && dashboard.state?.snapshot?.isAvailable != false
        // 复用已回归的纯函数：过去的重置时刻、现在以及无效偏移都不能伪装成实测 100%。
        let remaining = ScrubForecast.remainingPercent(window, now: now, offset: canPreview ? offset : 0)
        let refilled = canPreview && offset > 0 && resetsAt.map { $0 > now && $0 <= target } == true
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(BearTheme.series(ProviderPresentation.paletteIndex(provider), scheme))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(ProviderPresentation.name(provider) + " · " + window.label)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(ProviderPresentation.percent(remaining))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .layoutPriority(1)
            }
            Text(!canPreview ? "读数未确认，刷新后再预览"
                 : refilled ? "预计此时回满"
                 : resetsAt.map { $0 <= now ? "重置时间已过，等待刷新确认" : "回满于 " + Self.time($0, at: target) }
                    ?? "未提供重置时间")
                .font(.caption2)
                .foregroundStyle(BearTheme.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 14)
        }
        .foregroundStyle(BearTheme.text(scheme))
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
