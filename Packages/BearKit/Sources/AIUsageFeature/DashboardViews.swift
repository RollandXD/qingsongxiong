import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

@MainActor @Observable
public final class AIUsageNavigation {
    public var path: [ProviderID] = []
    public var relayID: UUID?
    public init() {}
    public func handle(components: [String]) -> Bool {
        if components.count == 2, components[0] == "relay", let id = UUID(uuidString: components[1]) {
            path = []; relayID = id; return true
        }
        guard let provider = AIUsageRoute.provider(components: components) else { return false }
        relayID = nil
        path = [provider]
        return true
    }
}

public struct AIUsageHome: View {
    @Bindable private var model: AIUsageModel
    @Bindable private var navigation: AIUsageNavigation
    private let relay: RelayModel?
    @State private var refreshHaptic = 0
    @State private var failureHaptic = 0
    @State private var thresholdHaptic = 0
    @State private var now = Date.now
    @State private var scrub: TimeInterval = 0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.bearReduceMotion) private var reduceMotion
    @Environment(\.bearOpenSettings) private var openSettings
    public init(model: AIUsageModel, navigation: AIUsageNavigation, relay: RelayModel? = nil) {
        self.model = model; self.navigation = navigation; self.relay = relay
    }
    public var body: some View {
        NavigationStack(path: $navigation.path) {
            homeScroll
        }
        .tint(BearTheme.accentInk(scheme))
        .sensoryFeedback(.success, trigger: refreshHaptic)
        .sensoryFeedback(.warning, trigger: failureHaptic)
        .sensoryFeedback(.warning, trigger: thresholdHaptic)
        .onChange(of: overview.mood) { (previous: DashboardOverviewPresentation.Mood, current: DashboardOverviewPresentation.Mood) in
            // 显式标注类型：这个复合条件让编译器推断超时（CI 42800582234 于此处报错）。
            guard previous != .asleep, current == .urgent, scenePhase == .active else { return }
            thresholdHaptic &+= 1
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // 冷启动：先把本机缓存（含中转）落到首帧，再走网络；网络回来只动差值。
            model.loadDashboard()
            await model.loadCached()
            await model.loadHistory()
            await relay?.load()
            // 中转列表真正加载完才清理指向已删账户的主卡；提前清会把用户的选择误抹。
            if let relay { model.pruneRelayCards(keeping: Set(relay.states.map(\.id))) }
            now = .now
            await model.refreshIfNeeded()
            await relay?.refreshIfNeeded()
            var ticks = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                now = .now
                ticks += 1
                if ticks % 5 == 0 {
                    await model.refreshIfNeeded()
                    await relay?.refreshIfNeeded()
                    await model.loadHistory()
                }
            }
        }
        .alert("暂未完成", isPresented: Binding(get: { navigation.path.isEmpty && model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }

    /// 首页滚动内容连同修饰符单独成块。
    /// 整条链塞进 body 时编译器推断超时（CI 42801375790 在 navigationDestination 处报错），
    /// 拆成独立表达式后两侧都只处理一半的修饰符。
    private var homeScroll: some View {
        ScrollView {
            homeContent
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(BearTheme.background(scheme).ignoresSafeArea())
        .navigationTitle("轻松熊")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { homeToolbar }
        .bearPullToRefresh(enabled: canRefresh) { await refreshAll() }
        .navigationDestination(item: $navigation.relayID) { id in
            relayDestination(id)
        }
        .navigationDestination(for: ProviderID.self) { provider in
            ProviderDetail(provider: provider, model: model)
        }
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            HoneyStatusCard(overview: overview, hero: hero)
            homeCardsSection
            recoveryPreview
            walletSection
            UsageTimelineSection(model: model, now: now, primary: model.dashboard.cards.compactMap { $0 }.first)
            otherAccountsSection
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 32)
    }

    /// 余额与中转：金额是主角，单独成区，不和百分比混排。
    private var walletSection: some View {
        HoneyWalletList(deepseek: dashboard(.deepseek), relay: relay,
                        onDeepSeek: { open(.provider(.deepseek)) },
                        onRelay: { id in navigation.path = []; navigation.relayID = id })
    }

    private var otherAccountsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("其他账户")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BearTheme.secondaryText(scheme))
                .padding(.horizontal, 16)
            OtherAccountsList(model: model, relay: relay, now: now) { ref in open(ref) }
        }
    }

    /// 中转详情要等中转列表加载完才有数据源，缺数据时不弹空页面。
    @ViewBuilder
    private func relayDestination(_ id: UUID) -> some View {
        if let relay {
            RelayDetail(id: id, model: relay)
        }
    }

    /// 工具栏单独成块：塞在 body 里会让整个 NavigationStack 表达式的类型推断超时。
    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: refreshAction) {
                BearRefreshGlyph(refreshing: isRefreshing, success: refreshHaptic, failure: failureHaptic)
            }
            .disabled(!canRefresh)
            .accessibilityLabel("刷新全部额度")
            .accessibilityIdentifier("refresh-all")
        }
        if let openSettings {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button(action: { openSettings() }) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
    }

    /// 任一来源在刷新就算刷新中，避免两个旋转指示器打架。
    private var isRefreshing: Bool {
        if !model.refreshing.isEmpty { return true }
        return !(relay?.refreshing.isEmpty ?? true)
    }

    private func refreshAction() {
        Task { await refreshAll() }
    }

    private static let jarProviders: [ProviderID] = [.codex, .claude]

    private func dashboard(_ provider: ProviderID) -> ProviderDashboardPresentation {
        ProviderDashboardPresentation(provider: provider, state: model.states[provider], at: now)
    }
    private var jars: [HoneyJarPresentation] { Self.jarProviders.map { HoneyJarPresentation(dashboard($0)) } }
    private var overview: DashboardOverviewPresentation {
        DashboardOverviewPresentation(providers: ProviderID.allCases.map(dashboard))
    }
    private var hero: HeroPresentation { HeroPresentation(overview: overview, jars: jars, now: now) }

    /// 主页只保留一个主卡区：两张卡的位置由用户自己选，蜜罐与中转余额同等大小。
    private var homeCardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("额度与余额").font(.footnote.weight(.semibold))
                Spacer()
                Text(freshness).font(.footnote).monospacedDigit().contentTransition(.opacity)
            }
            .foregroundStyle(BearTheme.secondaryText(scheme))
            .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 18) {
                HomeCardsSection(model: model, relay: relay, now: now, offset: 0) { ref in open(ref) }
            }
            .padding(16)
            .background(BearTheme.surface(scheme), in: .rect(cornerRadius: 26, style: .continuous))
        }
    }

    /// 独立恢复预览：时间尺与读数在同一屏，拖动时不用上下找数字。
    private var recoveryPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("恢复预览").font(.footnote.weight(.semibold))
                Spacer()
                Text(scrub == 0 ? "现在" : Self.offsetLabel(scrub))
                    .font(.footnote).monospacedDigit().contentTransition(.opacity)
            }
            .foregroundStyle(BearTheme.secondaryText(scheme))
            .padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 14) {
                TimeScrubber(offset: $scrub, now: now, marks: scrubMarks, enabled: hasConnectedProvider)
                RecoveryPreviewRows(model: model, now: now, offset: scrub)
            }
            .padding(16)
            .background(BearTheme.surface(scheme), in: .rect(cornerRadius: 26, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recovery-preview")
    }

    static func offsetLabel(_ offset: TimeInterval) -> String {
        let minutes = Int((offset / 60).rounded())
        if minutes < 60 { return "+ \(minutes) 分钟" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "+ \(hours) 小时" : "+ \(hours) 小时 \(rest) 分"
    }

    /// 只给已连接、且不重复的厂商窗口画刻度；中转没有重置周期，不强行画。
    private var scrubMarks: [TimeScrubber.Mark] {
        ProviderID.allCases.reduce(into: [TimeScrubber.Mark]()) { marks, provider in
            let jar = HoneyJarPresentation(dashboard(provider))
            guard jar.isConnected else { return }
            for window in [jar.fiveHour, jar.weekly].compactMap({ $0 }) {
                guard let offset = window.window.resetsAt?.timeIntervalSince(now),
                      offset > 0, offset <= TimeScrubber.range else { continue }
                marks.append(TimeScrubber.Mark(id: provider.rawValue + "." + window.id, offset: offset,
                    color: BearTheme.series(ProviderPresentation.paletteIndex(provider), scheme)))
            }
        }
    }

    private var hasConnectedProvider: Bool {
        ProviderID.allCases.contains { model.states[$0]?.connection == .connected }
    }

    /// 分节右上角：刷新反馈优先（失败优先于成功），否则显示最近读数的新鲜度。
    private var freshness: String {
        let feedback = ProviderID.allCases.compactMap { model.refreshFeedback[$0] }
        if let failed = feedback.first(where: { $0.contains("未完成") }) { return failed }
        if let first = feedback.first { return first }
        let fetched = Self.jarProviders.compactMap { model.states[$0]?.snapshot?.fetchedAt }.max()
        guard let fetched else { return "" }
        let minutes = Int(now.timeIntervalSince(fetched) / 60)
        return minutes < 1 ? "刚刚更新" : "\(minutes) 分钟前"
    }

    private func open(_ ref: AccountRef) {
        switch ref {
        case .provider(let provider):
            navigation.relayID = nil
            navigation.path.append(provider)
        case .relay(let id):
            navigation.relayID = id
        }
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
    @Environment(\.bearReduceMotion) private var reduceMotion
    private var presentation: ProviderDashboardPresentation {
        ProviderDashboardPresentation(provider: provider, state: model.states[provider], at: Date())
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let failure = presentation.state?.failure {
                    Label(AIUsageModel.explanation(failure), systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundStyle(BearTheme.warning(scheme))
                }
                if !presentation.windows.isEmpty { windows }
                if !jar.extras.isEmpty { extras }
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
                if provider == .deepseek {
                    Text("DeepSeek 官方 API 余额，与聊天会员分开计算。")
                        .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
                }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(BearTheme.background(scheme).ignoresSafeArea())
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
    private var jar: HoneyJarPresentation { HoneyJarPresentation(presentation) }
    @ViewBuilder private var windows: some View {
        let jar = self.jar
        if jar.fiveHour != nil || jar.weekly != nil {
            HoneyGroup("订阅额度", footer: "各窗口独立计算，比例不能相加。") {
                if let window = jar.fiveHour {
                    HoneyWindowRow(window: window, title: "5 小时", provider: provider, stale: presentation.isStale, now: Date())
                }
                if let window = jar.weekly {
                    HoneyWindowRow(window: window, title: "本周", provider: provider, stale: presentation.isStale, now: Date())
                }
            }
        }
    }
    private var extras: some View {
        HoneyGroup("附加限额", footer: "模型专属限制不代表全部模型的可用额度。") {
            ForEach(jar.extras) { window in
                HoneyWindowRow(window: window, title: window.shortLabel, provider: provider, stale: presentation.isStale, now: Date())
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
                }.padding(18).background(BearTheme.surface(scheme), in: .rect(cornerRadius: 26, style: .continuous))
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
