import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

// 首页「蜜位」：状态卡 + 每家一只双格蜜罐（左 5 小时、右本周）+ 时间尺。对应 design/prototype-honey。

extension HoneyJarPresentation {
    /// 时间尺偏移 `offset` 下的两格；未连接时为空罐。
    func cells(now: Date, offset: TimeInterval) -> [BearHoneyJar.Cell] {
        [(fiveHour, "5 小时"), (weekly, "本周")].map { window, label in
            guard let window, isConnected else { return BearHoneyJar.Cell(level: 0, warn: false, value: nil, label: label) }
            let remaining = ScrubForecast.remainingPercent(window, now: now, offset: offset)
            return BearHoneyJar.Cell(level: remaining / 100,
                                     warn: QuotaThresholds.level(remainingPercent: remaining) != .normal,
                                     value: String(Int(remaining.rounded())), label: label)
        }
    }

    var accessibilitySummary: String {
        guard isConnected else { return "未连接" }
        return [(fiveHour, "5 小时"), (weekly, "本周")].compactMap { window, label in
            window.map { label + "剩 " + ProviderPresentation.percent($0.remaining) }
        }.joined(separator: "，")
    }
}

/// 状态卡：一句人话 + 情绪熊。无障碍标签以情绪词开头（UI 测试按情绪词等待）。
struct HoneyStatusCard: View {
    let overview: DashboardOverviewPresentation
    let hero: HeroPresentation
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                headline
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BearTheme.text(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Text(hero.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            BearMoodMark(mood: overview.mood.bear).frame(width: 44, height: 44)
        }
        .padding(16)
        .background(BearTheme.surface(scheme), in: .rect(cornerRadius: 26, style: .continuous))
        .animation(BearMotion.smooth, value: hero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overview.moodLabel + "，" + hero.lead + hero.tail + "，" + hero.subtitle)
        .accessibilityIdentifier("dashboard-hero")
    }
    private var headline: Text {
        guard !hero.tail.isEmpty else { return Text(hero.lead) }
        return Text("\(hero.lead) \(Text(hero.tail).foregroundStyle(BearTheme.danger(scheme)))")
    }
}

/// 一家平台的蜜罐按钮：标题行 + 罐子 + 两格倒计时。
struct HoneyJarCard: View {
    let jar: HoneyJarPresentation
    let now: Date
    let offset: TimeInterval
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(BearTheme.series(ProviderPresentation.paletteIndex(jar.provider), scheme)).frame(width: 8, height: 8)
                Text(ProviderPresentation.name(jar.provider)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(BearTheme.text(scheme))
                Spacer(minLength: 4)
                if jar.isConnected {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        .foregroundStyle(BearTheme.secondaryText(scheme))
                } else {
                    Text("连接").font(.footnote).foregroundStyle(BearTheme.accentInk(scheme))
                }
            }
            .padding(.horizontal, 2)
            BearHoneyJar(cells: jar.cells(now: now, offset: offset), stale: jar.dashboard.isStale && jar.isConnected,
                         asleep: !jar.isConnected)
                .aspectRatio(156 / 220, contentMode: .fit)
            HStack(spacing: 0) {
                countdown(jar.fiveHour)
                countdown(jar.weekly)
            }
        }
        .contentShape(.rect)
    }

    @ViewBuilder private func countdown(_ window: UsageWindowPresentation?) -> some View {
        Group {
            if !jar.isConnected { Text("未连接") }
            else if let reset = window?.window.resetsAt {
                let left = reset.timeIntervalSince(now) - offset
                if reset <= now { Text("待刷新确认") }
                else if left <= 0 { Text("预计回满").fontWeight(.semibold).foregroundStyle(BearTheme.text(scheme)) }
                else {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                        Text(ResetCountdown.compact(left)).fontWeight(.semibold).foregroundStyle(BearTheme.text(scheme))
                    }
                }
            } else { Text("—") }
        }
        .font(.caption).monospacedDigit()
        .foregroundStyle(BearTheme.secondaryText(scheme))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .contentTransition(.numericText())
    }
}

/// 时间尺：按住拖动预览「之后不再使用」时各窗口何时回满；越过重置点吸附并给 selection 触觉，松手弹回现在。
struct TimeScrubber: View {
    @Binding var offset: TimeInterval
    let now: Date
    let marks: [Mark]
    let enabled: Bool
    static let range: TimeInterval = 7 * 86_400

    struct Mark: Identifiable, Equatable {
        let id: String
        let offset: TimeInterval
        let color: Color
    }

    @State private var dragging = false
    @State private var crossed = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bearReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(offset < 60 ? "回满预览" : ResetCountdown.moment(now.addingTimeInterval(offset), now: now))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(BearTheme.text(scheme))
                    .contentTransition(.numericText())
                Spacer()
                Text(!enabled ? "连接后可用" : offset < 60 ? "按住拖动" : "假设之后不再使用")
                    .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let x = width * min(1, max(0, offset / Self.range))
                ZStack(alignment: .topLeading) {
                    Capsule().fill(BearTheme.track(scheme)).frame(height: 4).offset(y: 20)
                    Capsule().fill(BearTheme.accent(scheme)).frame(width: x, height: 4).offset(y: 20)
                    ForEach(dayTicks, id: \.offset) { tick in
                        Text(tick.name).font(.caption2).foregroundStyle(BearTheme.secondaryText(scheme))
                            .fixedSize()
                            .position(x: width * tick.offset / Self.range, y: 40)
                    }
                    ForEach(Array(placedMarks.enumerated()), id: \.element.mark.id) { _, placed in
                        Circle().fill(placed.mark.color).frame(width: 8, height: 8)
                            .position(x: width * placed.mark.offset / Self.range, y: 10 - CGFloat(placed.lift) * 10)
                    }
                    Circle().fill(.white)
                        .frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .scaleEffect(dragging && !reduceMotion ? 1.15 : 1)
                        .position(x: min(width - 13, max(13, x)), y: 22)
                }
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled else { return }
                        if !dragging { withAnimation(BearMotion.snappy) { dragging = true } }
                        scrub(to: value.location.x / max(1, width) * Self.range)
                    }
                    .onEnded { _ in
                        withAnimation(reduceMotion ? BearMotion.quiet : BearMotion.smooth) { offset = 0; dragging = false }
                    })
            }
            .frame(height: 50)
        }
        // 禁用的是交互，不降低文字可读性。
        .sensoryFeedback(.selection, trigger: crossed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("回满预览")
        .accessibilityValue(offset < 60 ? "现在" : ResetCountdown.moment(now.addingTimeInterval(offset), now: now))
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            let stops = [0] + marks.map(\.offset).sorted()
            switch direction {
                case .increment: offset = stops.first { $0 > offset + 1 } ?? offset
                case .decrement: offset = stops.last { $0 < offset - 1 } ?? 0
                @unknown default: break
            }
        }
        .accessibilityIdentifier("time-scrubber")
    }

    /// 靠近重置点（±1.5% 量程）吸附；穿越的重置点数量变化即触发一次 selection 触觉。
    private func scrub(to raw: TimeInterval) {
        var value = min(Self.range, max(0, raw))
        if let snap = marks.min(by: { abs($0.offset - value) < abs($1.offset - value) }),
           abs(snap.offset - value) < Self.range * 0.015 { value = snap.offset }
        let before = marks.filter { $0.offset <= offset }.count
        let after = marks.filter { $0.offset <= value }.count
        offset = value
        if before != after { crossed &+= 1 }
    }

    /// 每天正午标星期名，最后一天不足半天时省略，避免贴边折行。
    private var dayTicks: [(offset: TimeInterval, name: String)] {
        let calendar = Calendar.current
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        let first = tomorrow.timeIntervalSince(now)
        return (0..<7).compactMap { day in
            let noon = first + Double(day) * 86_400 + 12 * 3_600
            guard noon / Self.range < 0.95 else { return nil }
            let date = now.addingTimeInterval(noon)
            return (noon, names[calendar.component(.weekday, from: date) - 1])
        }
    }

    /// 相近的重置点向上叠放，不互相遮挡。
    private var placedMarks: [(mark: Mark, lift: Int)] {
        var placed: [(mark: Mark, lift: Int)] = []
        for mark in marks.sorted(by: { $0.offset < $1.offset }) {
            var lift = 0
            while placed.contains(where: { abs($0.mark.offset - mark.offset) < Self.range * 0.025 && $0.lift == lift }) { lift += 1 }
            placed.append((mark, lift))
        }
        return placed
    }
}

/// 余额列表：设置式分组行，DeepSeek（CNY）与中转站（USD）分开，不与百分比混排。
struct HoneyWalletList: View {
    let deepseek: ProviderDashboardPresentation
    let relay: RelayModel?
    let onDeepSeek: () -> Void
    let onRelay: (UUID) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("余额").font(.footnote.weight(.semibold)).foregroundStyle(BearTheme.secondaryText(scheme))
                Spacer()
                if let relay {
                    NavigationLink { RelayAccountsView(model: relay) } label: {
                        Text("管理中转").font(.footnote)
                    }
                    .accessibilityIdentifier("relay-manage")
                }
            }
            .padding(.horizontal, 16)
            VStack(spacing: 0) {
                Button(action: onDeepSeek) { deepseekRow }
                    .buttonStyle(BearPressStyle())
                    .accessibilityIdentifier("provider-deepseek")
                if let relay {
                    ForEach(relay.states) { state in
                        Divider().padding(.leading, 60)
                        Button { onRelay(state.id) } label: { relayRow(state) }
                            .buttonStyle(BearPressStyle())
                            .accessibilityIdentifier("relay-account-" + state.id.uuidString)
                    }
                    if relay.states.isEmpty {
                        Divider().padding(.leading, 60)
                        NavigationLink { RelayAccountsView(model: relay) } label: {
                            row(icon: Image(systemName: "plus"), tint: BearTheme.track(scheme), iconInk: BearTheme.accentInk(scheme),
                                title: "添加中转站", detail: nil) { EmptyView() }
                        }
                        .buttonStyle(BearPressStyle())
                        .accessibilityIdentifier("relay-add-entry")
                    }
                }
            }
            .background(BearTheme.surface(scheme), in: .rect(cornerRadius: 26, style: .continuous))
            Text("各窗口独立计算，比例不能相加。")
                .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
                .padding(.horizontal, 16)
        }
    }

    private var deepseekRow: some View {
        let detail: String? = {
            guard let parts = deepseek.balances.first?.parts else { return deepseek.isConnectedForWallet ? nil : deepseek.connectionHint }
            return parts.map { $0.label + " " + NSDecimalNumber(decimal: $0.amount).stringValue }.joined(separator: " · ")
        }()
        return row(icon: Image(systemName: "water.waves"), tint: BearTheme.series(2, scheme), iconInk: .white,
                   title: "DeepSeek", detail: detail) {
            VStack(alignment: .trailing, spacing: 2) {
                if deepseek.balances.isEmpty { Text("—").foregroundStyle(BearTheme.secondaryText(scheme)) }
                ForEach(deepseek.balances) { balance in amount(balance.balance.total, currency: balance.balance.currency) }
            }
        }
    }

    private func relayRow(_ state: RelayState) -> some View {
        let presentation = RelayPresentation(state: state, at: Date())
        return row(icon: Image(systemName: "arrow.triangle.branch"), tint: BearTheme.relay(scheme), iconInk: .white,
                   title: state.account.displayName, detail: presentation.status) {
            Text(presentation.headline)
                .font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(BearTheme.text(scheme))
                .privacySensitive()
                .contentTransition(.numericText())
                .accessibilityLabel(presentation.fullValue)
        }
    }

    private func amount(_ value: Decimal, currency: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(currency).font(.caption2.weight(.semibold)).foregroundStyle(BearTheme.secondaryText(scheme))
            Text(NSDecimalNumber(decimal: value).stringValue)
                .font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
                .foregroundStyle(BearTheme.text(scheme))
                .contentTransition(.numericText())
        }
    }

    private func row<Trailing: View>(icon: Image, tint: Color, iconInk: Color, title: String, detail: String?,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            icon.font(.system(size: 15, weight: .semibold)).foregroundStyle(iconInk)
                .frame(width: 30, height: 30)
                .background(tint, in: .rect(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(BearTheme.text(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(BearTheme.secondaryText(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(BearTheme.secondaryText(scheme)).accessibilityHidden(true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(.rect)
    }
}

extension ProviderDashboardPresentation {
    var isConnectedForWallet: Bool { state?.connection == .connected }
}

/// 详情页的一行窗口：名称 + 剩余% + 横向蜜条 + 回满时刻。
struct HoneyWindowRow: View {
    let window: UsageWindowPresentation
    let title: String
    let provider: ProviderID
    let stale: Bool
    let now: Date
    @Environment(\.colorScheme) private var scheme
    private var warn: Bool { QuotaThresholds.level(remainingPercent: window.remaining) != .normal }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.body).foregroundStyle(BearTheme.text(scheme))
                Spacer(minLength: 8)
                Text(ProviderPresentation.percent(window.remaining))
                    .font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                    .foregroundStyle(warn ? BearTheme.danger(scheme) : BearTheme.text(scheme))
                    .contentTransition(.numericText(value: window.remaining))
            }
            BearHoneyBar(fraction: window.fraction, warn: warn, stale: stale)
            Text(resetText).font(.caption).monospacedDigit().foregroundStyle(BearTheme.secondaryText(scheme))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("window-" + provider.rawValue + "-" + window.id)
    }
    private var resetText: String {
        guard let reset = window.window.resetsAt else { return "未提供重置时间" }
        guard reset > now else { return "重置时间已过，等待刷新确认" }
        return ResetCountdown.moment(reset, now: now) + " 回满 · 还要 " + ResetCountdown.compact(reset.timeIntervalSince(now))
    }
}

/// 设置式分组：小标题 + 纸白卡片 + 行间分隔。
struct HoneyGroup<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.footer = footer; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(BearTheme.secondaryText(scheme))
                .padding(.horizontal, 16).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                        if index > 0 { Divider().padding(.leading, 16) }
                        subview
                    }
                }
            }
            .background(BearTheme.surface(scheme), in: .rect(cornerRadius: 26, style: .continuous))
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme)).padding(.horizontal, 16)
            }
        }
    }
}
