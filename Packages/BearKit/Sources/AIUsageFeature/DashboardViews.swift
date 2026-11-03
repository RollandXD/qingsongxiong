import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

@MainActor @Observable
public final class AIUsageNavigation {
    public var path: [ProviderID] = []
    var cardSource: ProviderID?
    public init() {}
    public func handle(components: [String]) -> Bool {
        guard let provider = AIUsageRoute.provider(components: components) else { return false }
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
    @State private var interaction = DashboardInteraction()
    @State private var refreshHaptic = 0
    @State private var appeared = false
    @Namespace private var navigationNamespace
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(model: AIUsageModel, navigation: AIUsageNavigation) {
        self.model = model; self.navigation = navigation
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
                    ForEach(ProviderID.allCases) { provider in card(provider) }
                }
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 24)
            }
            .background(BearTheme.background(scheme))
            .navigationTitle("轻松熊")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await refreshAll() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!model.refreshing.isEmpty || !model.connecting.isEmpty || model.clearing)
                    .accessibilityLabel("刷新全部额度").accessibilityIdentifier("refresh-all")
                }
            }
            .refreshable { await refreshAll() }
            .navigationDestination(for: ProviderID.self) { provider in
                ProviderDetail(provider: provider, model: model)
                    .modifier(ProviderNavigationTransition(provider: provider,
                        namespace: navigation.cardSource == provider && !reduceMotion ? navigationNamespace : nil))
            }
        }
        .tint(BearTheme.accent(scheme))
        .sensoryFeedback(.success, trigger: refreshHaptic)
        .onChange(of: model.states) { _, states in interaction.reconcile(states) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { appeared = true } }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.loadCached()
            interaction.reconcile(model.states)
            withAnimation(reduceMotion ? BearMotion.quiet : .easeOut(duration: 0.35)) { appeared = true }
            await model.refreshIfNeeded()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                await model.refreshIfNeeded()
            }
        }
        .alert("暂未完成", isPresented: Binding(get: { navigation.path.isEmpty && model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好") { model.message = nil }
        } message: { Text(model.message ?? "") }
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
            .opacity(appeared ? 1 : 0.75)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .animation(model.animatedRefresh.contains(provider) ? (reduceMotion ? BearMotion.quiet : BearMotion.data) : nil,
                       value: state?.snapshot?.fetchedAt)
            .animation(reduceMotion ? BearMotion.quiet : BearMotion.unfold, value: state?.connection)
    }
    private func refreshAll() async {
        let connected = ProviderID.allCases.filter { model.states[$0]?.connection == .connected }
        guard !connected.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for provider in connected { group.addTask { await model.refresh(provider, reportFailure: false) } }
        }
        if scenePhase == .active && connected.allSatisfy({ model.verifiedRefresh.contains($0) }) { refreshHaptic &+= 1 }
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
                if !presentation.balances.isEmpty { balances }
                if presentation.state?.snapshot == nil || presentation.state?.connection == .reconnectRequired { connection }
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
        .background(BearTheme.background(scheme))
        .foregroundStyle(BearTheme.text(scheme))
        .navigationTitle(ProviderPresentation.name(provider))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    if presentation.state?.connection == .connected {
                        Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
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
        .refreshable { await refresh() }
        .sensoryFeedback(.success, trigger: refreshHaptic)
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
    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            ProviderIdentity(presentation: presentation, refreshing: model.refreshing.contains(provider))
            HStack(spacing: 24) {
                DashboardMetric(presentation: presentation, focused: nil, large: true)
                if let window = presentation.summaryWindow {
                    BearQuotaArc(fraction: window.fraction,
                                 color: BearTheme.quotaColor(window.remaining, series: ProviderPresentation.paletteIndex(provider), scheme: scheme),
                                 stale: presentation.isStale).frame(width: 94, height: 94)
                }
            }
            if let window = presentation.summaryWindow {
                Text(window.role == .general ? "通用窗口中剩余比例最低" : window.role.label)
                    .font(.caption).foregroundStyle(BearTheme.secondaryText(scheme))
            }
        }.padding(22).background(BearTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 26))
    }
    private var windows: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("独立额度窗口").font(.title3.bold())
            ForEach(presentation.windows) { window in
                UsageWindowRow(window: window, provider: provider, stale: presentation.isStale,
                               selected: presentation.summaryWindow?.id == window.id)
                    .background(BearTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 17))
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
                }.padding(18).background(BearTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 20))
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
    private func refresh() async {
        guard presentation.state?.connection == .connected else { return }
        await model.refresh(provider, reportFailure: false)
        if scenePhase == .active && model.verifiedRefresh.contains(provider) { refreshHaptic &+= 1 }
    }
}
