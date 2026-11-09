import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

@MainActor @Observable
public final class AIUsageNavigation {
    public var path: [ProviderID] = []
    public var relayID: UUID?
    var cardSource: ProviderID?
    public init() {}
    public func handle(components: [String]) -> Bool {
        if components.count == 2, components[0] == "relay", let id = UUID(uuidString: components[1]) {
            path = []; relayID = id; cardSource = nil; return true
        }
        guard let provider = AIUsageRoute.provider(components: components) else { return false }
        relayID = nil
        cardSource = nil
        path = [provider]
        return true
    }
}

private struct ProviderNavigationTransition: ViewModifier {
    let provider: ProviderID
    let namespace: Namespace.ID?
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        if let namespace { content.navigationTransition(.zoom(sourceID: provider, in: namespace)) }
        else { content }
        #else
        content
        #endif
    }
}

public struct AIUsageHome: View {
    @Bindable private var model: AIUsageModel
    @Bindable private var navigation: AIUsageNavigation
    private let relay: RelayModel?
    @State private var interaction = DashboardInteraction()
    @State private var refreshHaptic = 0
    @State private var failureHaptic = 0
    @State private var thresholdHaptic = 0
    @State private var appeared = false
    @Namespace private var navigationNamespace
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(model: AIUsageModel, navigation: AIUsageNavigation, relay: RelayModel? = nil) {
        self.model = model; self.navigation = navigation; self.relay = relay
    }
    public var body: some View {
        NavigationStack(path: $navigation.path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("AI 额度").font(.title2.bold()).foregroundStyle(BearTheme.text(scheme))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                    }.padding(.horizontal, 3).padding(.bottom, 3)
                    DashboardHero(overview: overview, entered: appeared)
                        .opacity(appeared ? 1 : 0)
                        .transition(.blurReplace)
                        .offset(y: appeared || reduceMotion ? 0 : 10)
                        .padding(.bottom, 4)
                    ForEach(Array(ProviderID.allCases.enumerated()), id: \.element) { index, provider in
                        card(provider)
                            .opacity(appeared ? 1 : 0)
                            .transition(.blurReplace)
                            .offset(y: appeared || reduceMotion ? 0 : 12)
                            .animation(BearMotion.choose(BearMotion.entrance, reduceMotion: reduceMotion)
                                .delay(reduceMotion ? 0 : Double(index + 1) * BearMotion.stagger * 2), value: appeared)
                    }
                    if let relay { RelayHomeSection(model: relay, onSelect: { navigation.relayID = $0 }) }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background(BearTheme.paper(scheme).ignoresSafeArea())
            .navigationTitle("轻松熊")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await refreshAll() } } label: {
                        BearRefreshGlyph(refreshing: !model.refreshing.isEmpty || !(relay?.refreshing.isEmpty ?? true), success: refreshHaptic, failure: failureHaptic)
                    }
                    .disabled(!canRefresh)
                    .accessibilityLabel("刷新全部额度").accessibilityIdentifier("refresh-all")
                }
            }
            .bearPullToRefresh(enabled: canRefresh) { await refreshAll() }
            .navigationDestination(item: $navigation.relayID) { id in
                if let relay { RelayDetail(id: id, model: relay) }
            }
            .navigationDestination(for: ProviderID.self) { provider in
                ProviderDetail(provider: provider, model: model)
                    .modifier(ProviderNavigationTransition(provider: provider,
                        namespace: navigation.cardSource == provider && !reduceMotion ? navigationNamespace : nil))
            }
        }
        .tint(BearTheme.accent(scheme))
        .sensoryFeedback(.success, trigger: refreshHaptic)
        .sensoryFeedback(.warning, trigger: failureHaptic)
        .sensoryFeedback(.warning, trigger: thresholdHaptic)
        .onChange(of: overview.mood) { old, new in
            if old != .asleep && new == .urgent && scenePhase == .active { thresholdHaptic &+= 1 }
        }
        .onChange(of: model.states) { _, states in interaction.reconcile(states) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { appeared = true } }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.loadCached()
            interaction.reconcile(model.states)
            withAnimation(BearMotion.choose(BearMotion.entrance, reduceMotion: reduceMotion)) { appeared = true }
            await model.refreshIfNeeded()
            await relay?.refreshIfNeeded()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                await model.refreshIfNeeded()
                await relay?.refreshIfNeeded()
            }
        }
        .alert("暂未完成", isPresented: Binding(get: { navigation.path.isEmpty && model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
    private var overview: DashboardOverviewPresentation {
        DashboardOverviewPresentation(providers: ProviderID.allCases.map {
            ProviderDashboardPresentation(provider: $0, state: model.states[$0], at: Date())
        })
    }
    private func card(_ provider: ProviderID) -> some View {
        let state = model.states[provider]
        let presentation = ProviderDashboardPresentation(provider: provider, state: state, at: Date())
        return DashboardProviderCard(presentation: presentation,
            expanded: interaction.expandedProvider == provider, focusedID: interaction.focusedWindows[provider],
            refreshing: model.refreshing.contains(provider), feedback: model.refreshFeedback[provider],
            navigationNamespace: navigationNamespace,
            onNavigate: { navigation.cardSource = provider },
            onToggle: {
                withAnimation(reduceMotion ? BearMotion.quiet : BearMotion.unfold) { interaction.toggle(provider) }
            },
            onFocus: { id in
                withAnimation(reduceMotion ? BearMotion.quiet : BearMotion.unfold) { interaction.focus(id, for: provider) }
            })
            .id(provider)
            .animation(model.animatedRefresh.contains(provider) ? (reduceMotion ? BearMotion.quiet : BearMotion.data) : nil,
                       value: state?.snapshot?.fetchedAt)
            .animation(reduceMotion ? BearMotion.quiet : BearMotion.unfold, value: state?.connection)
    }
    private var canRefresh: Bool {
        let hasAccounts = model.states.values.contains(where: { $0.connection == .connected }) || !(relay?.states.isEmpty ?? true)
        return hasAccounts && model.refreshing.isEmpty && model.connecting.isEmpty && !model.clearing
            && (relay?.refreshing.isEmpty ?? true) && !(relay?.saving ?? false) && !(relay?.clearing ?? false)
    }
    @discardableResult
    private func refreshAll() async -> Bool {
        let connected = ProviderID.allCases.filter { model.states[$0]?.connection == .connected }
        let relayIDs = relay?.states.map(\.id) ?? []
        guard !connected.isEmpty || !relayIDs.isEmpty else { return false }
        let succeeded = await withTaskGroup(of: Bool.self) { group in
            for provider in connected {
                group.addTask {
                    await model.refresh(provider, reportFailure: false)
                    return await model.verifiedRefresh.contains(provider)
                }
            }
            if let relay { for id in relayIDs { group.addTask { await relay.refresh(id, report: false) } } }
            var allSucceeded = true
            for await result in group { if !result { allSucceeded = false } }
            return allSucceeded
        }
        if scenePhase == .active && !Task.isCancelled {
            if succeeded { refreshHaptic &+= 1 } else { failureHaptic &+= 1 }
        }
        return succeeded
    }
}

public struct AIUsageAccountSettings: View {
    private let model: AIUsageModel
    public init(model: AIUsageModel) { self.model = model }
    public var body: some View {
        ForEach(ProviderID.allCases) { provider in
            NavigationLink(ProviderPresentation.name(provider)) { ProviderDetail(provider: provider, model: model) }
        }
    }
}

struct ProviderDetail: View {
    let provider: ProviderID
    @Bindable var model: AIUsageModel
    @State private var showKeyEntry = false
    @State private var confirmDisconnect = false
    @State private var refreshHaptic = 0
    @State private var failureHaptic = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var presentation: ProviderDashboardPresentation {
        ProviderDashboardPresentation(provider: provider, state: model.states[provider], at: Date())
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if let failure = presentation.state?.failure {
                    Label(AIUsageModel.explanation(failure), systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(BearTheme.warning(scheme))
                }
                if !presentation.windows.isEmpty { windows }
                if !presentation.resetTimeline.isEmpty {
                    WindowResetTimeline(presentation: presentation)
                }
                if !presentation.balances.isEmpty { balances }
                if (presentation.state?.snapshot == nil && presentation.state?.connection != .connected) || presentation.state?.connection == .reconnectRequired { connection }
                if let snapshot = presentation.state?.snapshot {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("数据时间").font(.caption.weight(.semibold))
                        Text(snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))
                        if presentation.isStale { Text("当前为上次读取结果，等待服务端确认。") }
                        if let feedback = model.refreshFeedback[provider] { Text(feedback) }
                    }.font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
                }
                Text(provider == .deepseek ? "DeepSeek 官方 API 余额，与聊天会员分开计算。" : "各额度窗口独立计算。模型专属限制不代表全部模型的可用额度。")
                    .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
            }.padding(20)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(BearTheme.paper(scheme).ignoresSafeArea())
        .foregroundStyle(BearTheme.text(scheme))
        .navigationTitle(ProviderPresentation.name(provider))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if presentation.state?.connection == .connected {
                        Button { Task { await refresh() } } label: {
                            BearRefreshGlyph(refreshing: model.refreshing.contains(provider), success: refreshHaptic, failure: failureHaptic)
                        }
                            .disabled(model.refreshing.contains(provider))
                            .accessibilityLabel("刷新数据").accessibilityIdentifier("refresh-" + provider.rawValue)
                    }
                    Menu {
                        Button("更换账户") { connect() }.disabled(model.connecting.contains(provider) || model.clearing)
                        if presentation.state?.connection != .disconnected {
                            Button("退出账户", role: .destructive) { confirmDisconnect = true }
                        }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("账户操作")
                }
            }
        }
        .bearPullToRefresh(enabled: presentation.state?.connection == .connected && !model.refreshing.contains(provider)) { await refresh() }
        .sensoryFeedback(.success, trigger: refreshHaptic)
        .sensoryFeedback(.warning, trigger: failureHaptic)
        .animation(model.animatedRefresh.contains(provider) ? (reduceMotion ? BearMotion.quiet : BearMotion.data) : nil,
                   value: presentation.state?.snapshot?.fetchedAt)
        .sheet(isPresented: $showKeyEntry) {
            APIKeySheet(model: model)
            #if os(iOS)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            #endif
        }
        .alert("暂未完成", isPresented: Binding(get: { !showKeyEntry && model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .confirmationDialog("退出后会清除本机凭据和该平台缓存。", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("退出账户", role: .destructive) { Task { await model.disconnect(provider) } }
        }
    }
    private var series: Color { BearTheme.series(ProviderPresentation.paletteIndex(provider), scheme) }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            ProviderIdentity(presentation: presentation, refreshing: model.refreshing.contains(provider))
            HStack(spacing: 24) {
                DashboardMetric(presentation: presentation, focused: nil, large: true)
                if let window = presentation.summaryWindow {
                    BearRing(fraction: window.fraction,
                             color: BearTheme.quotaColor(window.remaining, series: ProviderPresentation.paletteIndex(provider), scheme: scheme),
                             stale: presentation.isStale, lineWidth: 11)
                        .frame(width: 112, height: 112)
                        .accessibilityHidden(true)
                }
            }
            if let window = presentation.summaryWindow {
                Text(window.role == .general ? "通用窗口中剩余比例最低" : window.role.label)
                    .font(.caption).foregroundStyle(BearTheme.secondaryText(scheme))
            }
        }.padding(22).bearGlassCard(tint: series, cornerRadius: 30)
    }
    private var windows: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("独立额度窗口").font(.title3.bold())
            ForEach(presentation.windows) { window in
                UsageWindowRow(window: window, provider: provider, stale: presentation.isStale,
                               selected: presentation.summaryWindow?.id == window.id)
                    .bearGlassCard(tint: series, cornerRadius: 20)
            }
        }
    }
    private var balances: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("余额组成").font(.title3.bold())
            ForEach(presentation.balances) { balance in
                VStack(alignment: .leading, spacing: 14) {
                    Text(ProviderPresentation.money(balance.balance.total, currency: balance.balance.currency)).font(.headline).textSelection(.enabled)
                    BalanceBreakdown(balance: balance, color: BearTheme.series(ProviderPresentation.paletteIndex(provider), scheme))
                }.padding(18).bearGlassCard(tint: series, cornerRadius: 22)
            }
            if let available = presentation.state?.snapshot?.isAvailable {
                Label((presentation.isStale ? "上次读取：" : "") + (available ? "余额可继续调用" : "余额不足以继续调用"),
                      systemImage: available ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(available ? BearTheme.success(scheme) : BearTheme.warning(scheme))
            }
        }
    }
    private var connection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("连接账户", action: connect).buttonStyle(.glassProminent)
                .disabled(!model.canConnect(provider) || model.connecting.contains(provider) || model.clearing)
                .accessibilityIdentifier("connect-" + provider.rawValue)
            if model.connecting.contains(provider) { ProgressView("正在等待官方授权…") }
            Text(provider == .deepseek ? "密钥只在手机安全字段输入。" : "请在平台官方页面核对授权内容；轻松熊只读取额度，不发送模型请求。")
                .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
        }
    }
    private func connect() {
        if provider == .deepseek { showKeyEntry = true }
        else { Task { await model.connect(provider, key: nil) } }
    }
    @discardableResult
    private func refresh() async -> Bool {
        guard presentation.state?.connection == .connected else { return false }
        await model.refresh(provider, reportFailure: false)
        let succeeded = model.verifiedRefresh.contains(provider)
        if scenePhase == .active && !Task.isCancelled {
            if succeeded { refreshHaptic &+= 1 } else { failureHaptic &+= 1 }
        }
        return succeeded
    }
}
