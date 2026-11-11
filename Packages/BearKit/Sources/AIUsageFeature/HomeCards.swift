import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

/// 两张主卡 + 空位选择。位置固定两名，用户自己决定放谁。
struct HomeCardsSection: View {
    let model: AIUsageModel
    let relay: RelayModel?
    let now: Date
    let offset: TimeInterval
    let freshness: String
    let onOpen: (AccountRef) -> Void

    @State private var pickingSlot: Int?
    @State private var availableWidth: CGFloat = 360
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme

    /// 可放进主卡的候选：已连接的厂商账户 + 所有中转账户。
    private var candidates: [AccountRef] {
        ProviderID.allCases.compactMap { provider in
            model.states[provider]?.connection == .connected ? AccountRef.provider(provider) : nil
        } + (relay?.states.map { AccountRef.relay($0.id) } ?? [])
    }

    private func source(for ref: AccountRef?) -> HomeCardSource? {
        HomeCardSource.resolve(ref, states: model.states, relays: relay?.states ?? [], at: now)
    }

    private func name(for ref: AccountRef) -> String {
        switch ref {
        case .provider(let provider): ProviderPresentation.name(provider)
        case .relay(let id): relay?.states.first(where: { $0.id == id })?.account.displayName ?? "中转账户"
        }
    }

    private var cardLayout: AnyLayout {
        typeSize.isAccessibilitySize || availableWidth < 300
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("额度与余额").font(.footnote.weight(.semibold))
                Spacer(minLength: 4)
                Text(freshness).font(.footnote).monospacedDigit().contentTransition(.opacity)
                    .fixedSize(horizontal: false, vertical: true)
                Menu {
                    ForEach(Array(0..<DashboardPreferences.slotCount), id: \.self) { slot in
                        Button("更换第 \(slot + 1) 张卡") { pickingSlot = slot }
                            .accessibilityIdentifier("home-card-edit-" + String(slot))
                    }
                    Button("交换两张卡") { model.swapCards() }
                        .accessibilityIdentifier("home-cards-swap")
                } label: {
                    Text("编辑").font(.footnote.weight(.semibold))
                        .foregroundStyle(BearTheme.accentInk(scheme))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("home-cards-edit")
                .accessibilityLabel("编辑首页主卡")
            }
            .foregroundStyle(BearTheme.secondaryText(scheme))
            .padding(.horizontal, 16)
            cardLayout {
                ForEach(Array(0..<DashboardPreferences.slotCount), id: \.self) { slot in
                    slotView(slot)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .padding(16)
            .background(BearTheme.surface(scheme), in: .rect(cornerRadius: 26, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home-cards")
        }
        .sheet(item: Binding(get: { pickingSlot.map(HomeSlot.init) }, set: { if $0 == nil { pickingSlot = nil } })) { slot in
            HomeCardPicker(candidates: candidates, current: model.dashboard.ref(atSlot: slot.id),
                           name: name) { ref in
                model.setCard(ref, atSlot: slot.id)
                pickingSlot = nil
            } onClear: {
                model.setCard(nil, atSlot: slot.id)
                pickingSlot = nil
            }
        }
    }

    @ViewBuilder private func slotView(_ slot: Int) -> some View {
        let ref = model.dashboard.ref(atSlot: slot)
        if let source = source(for: ref) {
            Button {
                onOpen(source.ref)
            } label: {
                card(source)
            }
            .buttonStyle(BearPressStyle())
            .accessibilityLabel(name(for: source.ref))
            .accessibilityValue(accessibilityValue(source))
            .accessibilityHint("查看详情；长按可更换卡片")
            // 按钮按“点开谁”命名，外层容器再标位置：两套读写互不覆盖。
            .accessibilityIdentifier(source.ref.accessibilityID)
            .contextMenu {
                Button {
                    model.swapCards()
                } label: { Label("交换两张卡", systemImage: "arrow.left.arrow.right") }
                Button {
                    pickingSlot = slot
                } label: { Label("更换这张卡", systemImage: "square.on.square") }
                Button(role: .destructive) {
                    model.setCard(nil, atSlot: slot)
                } label: { Label("移出首页", systemImage: "minus.circle") }
            }
            .slotFrame(slot)
        } else {
            Button { pickingSlot = slot } label: { emptySlot(ref) }
                .buttonStyle(BearPressStyle())
                .accessibilityLabel(ref == nil ? "选择账户" : name(for: ref!) + " 已不可用，点击更换")
                .accessibilityIdentifier("home-card-empty-" + String(slot))
                .slotFrame(slot)
        }
    }

    @ViewBuilder private func card(_ source: HomeCardSource) -> some View {
        switch source {
        case .provider(let jar):
            HoneyJarCard(jar: jar, now: now, offset: offset)
                .frame(maxWidth: .infinity)
        case .providerBalance(let presentation):
            ProviderBalanceHomeTile(presentation: presentation)
        case .relay(let presentation):
            RelayHomeTile(presentation: presentation)
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        case .unconnected(let provider):
            UnconnectedProviderTile(provider: provider)
                .frame(maxWidth: .infinity)
        }
    }

    private func accessibilityValue(_ source: HomeCardSource) -> String {
        switch source {
        case .provider(let jar): jar.accessibilitySummary
        case .providerBalance(let presentation):
            (presentation.balances.isEmpty ? "暂无余额读数" : presentation.balances.map {
                ProviderPresentation.money($0.balance.total, currency: $0.balance.currency)
            }.joined(separator: "，")) + "，" + presentation.status
        case .relay(let presentation): presentation.headline + "，" + presentation.status
        case .unconnected(let provider): ProviderPresentation.name(provider) + " 未连接"
        }
    }

    /// 空位也要说明白：是没选，还是原来那个账户被删/退出了。
    private func emptySlot(_ ref: AccountRef?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.circle.dashed").font(.title2)
                .foregroundStyle(BearTheme.secondaryText(scheme))
            Text(ref == nil ? "选择账户" : "账户已移除")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BearTheme.text(scheme))
            if let ref {
                Text(name(for: ref))
                    .font(.caption2)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
                    .lineLimit(1)
            }
            Text("点击选择")
                .font(.caption2)
                .foregroundStyle(BearTheme.secondaryText(scheme))
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .padding(14)
        .background(BearTheme.surface(scheme).opacity(0.6),
                    in: .rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(BearTheme.separator(scheme), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }
}

/// sheet(item:) 需要 Identifiable；位置号本身不够唯一，用它包一层。
private struct HomeSlot: Identifiable {
    let id: Int
    init(_ id: Int) { self.id = id }
}

/// 未连接厂商卡：占住用户选的位置，明确指出去哪连接。
///
/// 尺寸与蜜罐卡一致，避免未连接时首页突然塌陷成两行小字。
struct UnconnectedProviderTile: View {
    let provider: ProviderID
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .strokeBorder(BearTheme.secondaryText(scheme), lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                Text(ProviderPresentation.name(provider))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BearTheme.text(scheme))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    // 窄卡里名字优先占位，不让右侧图标把它挤成截断。
                    .layoutPriority(1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BearTheme.secondaryText(scheme))
            }
            .padding(.horizontal, 2)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("未连接")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(BearTheme.text(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("点按完成连接")
                    .font(.caption)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
        .padding(14)
        .background(BearTheme.surface(scheme).opacity(0.55),
                    in: .rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(BearTheme.separator(scheme), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }
}

/// 中转主卡：金额当主角，跟蜜罐同一体量与节奏，不假装成百分比。
struct RelayHomeTile: View {
    let presentation: RelayPresentation
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(BearTheme.relay(scheme)).frame(width: 8, height: 8)
                Text(presentation.state.account.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BearTheme.text(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(BearTheme.secondaryText(scheme))
            }
            .padding(.horizontal, 2)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                // 多币种不能合并成一个数：逐行保留币种代码与金额，否则用户会以为只掉了一种币。
                if balances.count > 1 {
                    ForEach(balances, id: \.currency) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.currency)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BearTheme.secondaryText(scheme))
                            Text(Self.amount(item.total))
                                .font(.system(.title3, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(BearTheme.text(scheme))
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    Text(amountText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .foregroundStyle(BearTheme.text(scheme))
                }
                Text(presentation.state.account.site.displayName)
                    .font(.caption)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: presentation.isStale ? "clock.badge.exclamationmark" : "checkmark.circle")
                Text(presentation.status).lineLimit(2)
            }
            .font(.caption)
            .foregroundStyle(presentation.isStale ? BearTheme.warning(scheme) : BearTheme.secondaryText(scheme))
            .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(.rect)
    }

    /// 金额为主、币种随行；多币种时只显示第一个并在详情里看全。
    private var balances: [CurrencyBalance] {
        presentation.state.snapshot?.balances ?? []
    }

    /// 金额只负责数字；币种代码是独立标签，两者都在无障碍树里各有一份。
    private static func amount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    private var amountText: String {
        guard let balance = presentation.state.snapshot?.balances.first else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSDecimalNumber(decimal: balance.total)) ?? "—"
        return balance.currency + " " + number
    }
}

/// 换卡选择器：只列真正能放的账户，空卡不制造“已连接”的错觉。
struct HomeCardPicker: View {
    let candidates: [AccountRef]
    let current: AccountRef?
    let name: (AccountRef) -> String
    let onPick: (AccountRef) -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView("还没有可显示的账户", systemImage: "person.crop.circle.badge.questionmark",
                                           description: Text("先在设置里连接厂商账户，或添加一个中转站。"))
                } else {
                    List {
                        Section("可放到首页") {
                            ForEach(candidates, id: \.id) { ref in
                                Button {
                                    onPick(ref)
                                } label: {
                                    HStack {
                                        Text(name(ref)).foregroundStyle(BearTheme.text(scheme))
                                        Spacer()
                                        if ref == current {
                                            Image(systemName: "checkmark").foregroundStyle(BearTheme.accentInk(scheme))
                                        }
                                    }
                                }
                                .accessibilityIdentifier("pick-" + ref.id)
                            }
                        }
                        if current != nil {
                            Section {
                                Button(role: .destructive) { onClear() } label: { Text("移出首页") }
                                    .accessibilityIdentifier("home-card-remove")
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择卡片")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

/// 没进两张主卡的其他账户：紧凑一行，状态在前，点开看详情。
struct OtherAccountsList: View {
    let model: AIUsageModel
    let relay: RelayModel?
    let now: Date
    let onOpen: (AccountRef) -> Void
    @Environment(\.colorScheme) private var scheme

    private var rows: [AccountRef] {
        let shown = Set(model.dashboard.selectedRefs)
        // 未连接的厂商也要留入口：否则第三个账户在首页既不上卡也无法连接，就彻底找不到了。
        // 余额区的 DeepSeek 不在此重复，避免同一个账户在无障碍树里出现两次。
        let providers = ProviderID.allCases.compactMap { provider -> AccountRef? in
            guard provider != .deepseek else { return nil }
            let ref = AccountRef.provider(provider)
            return shown.contains(ref) ? nil : ref
        }
        // 中转账户已在余额区逐行展示，不在此重复。
        return providers
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, ref in
                    Button { onOpen(ref) } label: { row(ref) }
                        .buttonStyle(.plain)
                        // 与主卡同一个账户标识：无论账户在上卡还是在列表里，都能按名字找到。
                        .accessibilityIdentifier(ref.accessibilityID)
                    if index < rows.count - 1 {
                        Divider().overlay(BearTheme.separator(scheme)).padding(.leading, 42)
                    }
                }
            }
            .background(BearTheme.surface(scheme), in: .rect(cornerRadius: 20, style: .continuous))
        }
    }

    @ViewBuilder private func row(_ ref: AccountRef) -> some View {
        HStack(spacing: 12) {
            Circle().fill(tint(ref)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(ref)).font(.subheadline)
                    .foregroundStyle(BearTheme.text(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle(ref)).font(.caption)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(BearTheme.secondaryText(scheme))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(.rect)
    }

    private func tint(_ ref: AccountRef) -> Color {
        switch ref {
        case .provider(let provider):
            BearTheme.series(ProviderPresentation.paletteIndex(provider), scheme)
        case .relay: BearTheme.relay(scheme)
        }
    }

    private func title(_ ref: AccountRef) -> String {
        switch ref {
        case .provider(let provider): ProviderPresentation.name(provider)
        case .relay(let id): relay?.states.first(where: { $0.id == id })?.account.displayName ?? "中转账户"
        }
    }

    private func subtitle(_ ref: AccountRef) -> String {
        switch ref {
        case .provider(let provider):
            let dashboard = ProviderDashboardPresentation(provider: provider, state: model.states[provider], at: now)
            guard model.states[provider]?.connection == .connected else { return "未连接 · 去连接" }
            guard let window = dashboard.summaryWindow else { return "已连接" }
            return "剩 " + ProviderPresentation.percent(window.remaining) + " · " + window.shortLabel
        case .relay(let id):
            guard let state = relay?.states.first(where: { $0.id == id }) else { return "中转账户" }
            return RelayPresentation(state: state, at: now).headline
        }
    }
}

/// 主卡的两个身份：位置（第几张）与目标（点开哪个账户）。
///
/// 位置用于断言“两张同级、可交换”；目标沿用 0.4 的可达性探针
/// （`provider-codex` 等），既有测试不必为了新信息架构而放宽。
enum HomeCardSlot {
    static func identifier(for ref: AccountRef) -> String {
        switch ref {
        case .provider(let provider): "provider-" + provider.rawValue
        case .relay(let id): "relay-" + id.uuidString
        }
    }
}

private struct SlotFrame: ViewModifier {
    let slot: Int
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home-card-" + String(slot))
    }
}

extension View {
    /// 外层位置标识；与内部按钮的目标标识共存，不覆盖。
    func slotFrame(_ slot: Int) -> some View { modifier(SlotFrame(slot: slot)) }
}
