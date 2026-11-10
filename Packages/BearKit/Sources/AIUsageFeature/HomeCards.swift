import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

/// 首页主卡：厂商蜜罐与中转余额平级占据同样大小的位置，谁都不是“次要卡片”。
enum HomeCardSource: Equatable {
    case provider(HoneyJarPresentation)
    case relay(RelayPresentation)

    var ref: AccountRef {
        switch self {
        case .provider(let jar): .provider(jar.provider)
        case .relay(let presentation): .relay(presentation.state.id)
        }
    }

    var isConnected: Bool {
        switch self {
        case .provider(let jar): jar.isConnected
        case .relay(let presentation): presentation.state.snapshot != nil
        }
    }
}

/// 两张主卡 + 空位选择。位置固定两名，用户自己决定放谁。
struct HomeCardsSection: View {
    let model: AIUsageModel
    let relay: RelayModel?
    let now: Date
    let offset: TimeInterval
    let onOpen: (AccountRef) -> Void

    @State private var pickingSlot: Int?
    @Environment(\.colorScheme) private var scheme

    /// 可放进主卡的候选：已连接的厂商账户 + 所有中转账户。
    private var candidates: [AccountRef] {
        ProviderID.allCases.compactMap { provider in
            model.states[provider]?.connection == .connected ? AccountRef.provider(provider) : nil
        } + (relay?.states.map { AccountRef.relay($0.id) } ?? [])
    }

    private func source(for ref: AccountRef?) -> HomeCardSource? {
        guard let ref else { return nil }
        switch ref {
        case .provider(let provider):
            guard let state = model.states[provider], state.connection == .connected else { return nil }
            return .provider(HoneyJarPresentation(ProviderDashboardPresentation(provider: provider, state: state, at: now)))
        case .relay(let id):
            guard let state = relay?.states.first(where: { $0.id == id }) else { return nil }
            return .relay(RelayPresentation(state: state, at: now))
        }
    }

    private func name(for ref: AccountRef) -> String {
        switch ref {
        case .provider(let provider): ProviderPresentation.name(provider)
        case .relay(let id): relay?.states.first(where: { $0.id == id })?.account.displayName ?? "中转账户"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(0..<DashboardPreferences.slotCount), id: \.self) { slot in
                slotView(slot)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-cards")
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
            .accessibilityIdentifier("home-card-" + String(slot))
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
        } else {
            Button { pickingSlot = slot } label: { emptySlot(ref) }
                .buttonStyle(BearPressStyle())
                .accessibilityLabel(ref == nil ? "选择账户" : name(for: ref!) + " 已不可用，点击更换")
                .accessibilityIdentifier("home-card-empty-" + String(slot))
        }
    }

    @ViewBuilder private func card(_ source: HomeCardSource) -> some View {
        switch source {
        case .provider(let jar):
            HoneyJarCard(jar: jar, now: now, offset: offset)
                .frame(maxWidth: .infinity)
        case .relay(let presentation):
            RelayHomeTile(presentation: presentation)
                .frame(maxWidth: .infinity)
        }
    }

    private func accessibilityValue(_ source: HomeCardSource) -> String {
        switch source {
        case .provider(let jar): jar.accessibilitySummary
        case .relay(let presentation): presentation.headline + "，" + presentation.status
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
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(BearTheme.secondaryText(scheme))
            }
            .padding(.horizontal, 2)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text(amountText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(BearTheme.text(scheme))
                Text(presentation.state.account.site.displayName)
                    .font(.caption)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: presentation.isStale ? "clock.badge.exclamationmark" : "checkmark.circle")
                Text(presentation.status).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(presentation.isStale ? BearTheme.warning(scheme) : BearTheme.secondaryText(scheme))
            .fixedSize(horizontal: false, vertical: true)
        }
        .contentShape(.rect)
    }

    /// 金额为主、币种随行；多币种时只显示第一个并在详情里看全。
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
        let providers = ProviderID.allCases.compactMap { provider -> AccountRef? in
            guard model.states[provider]?.connection == .connected else { return nil }
            let ref = AccountRef.provider(provider)
            return shown.contains(ref) ? nil : ref
        }
        let relays = (relay?.states ?? []).compactMap { state -> AccountRef? in
            let ref = AccountRef.relay(state.id)
            return shown.contains(ref) ? nil : ref
        }
        return providers + relays
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, ref in
                    Button { onOpen(ref) } label: { row(ref) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("other-account-" + ref.id)
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
                Text(subtitle(ref)).font(.caption)
                    .foregroundStyle(BearTheme.secondaryText(scheme))
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
            guard let window = dashboard.summaryWindow else { return "已连接" }
            return "剩 " + Int(window.remaining.rounded()) + "% · " + window.shortLabel
        case .relay(let id):
            guard let state = relay?.states.first(where: { $0.id == id }) else { return "中转账户" }
            return RelayPresentation(state: state, at: now).headline
        }
    }
}
