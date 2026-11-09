import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import SwiftUI

struct RelayHomeSection: View {
    @Bindable var model: RelayModel
    let onSelect: (UUID) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("中转额度").font(.title3.bold())
                    Text("独立账户，不与订阅额度合并").font(.caption).foregroundStyle(BearTheme.secondaryText(scheme))
                }
                Spacer()
                NavigationLink { RelayAccountsView(model: model) } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.glass).accessibilityLabel("管理中转账户").accessibilityIdentifier("relay-manage")
            }
            ForEach(model.states) { state in
                Button { onSelect(state.id) } label: { RelayBalanceCard(state: state) }
                    .buttonStyle(BearLiftPressStyle()).accessibilityIdentifier("relay-account-" + state.id.uuidString)
            }
            if model.states.isEmpty {
                NavigationLink { RelayAccountsView(model: model) } label: {
                    Label("添加 APIKEY.FAN 账户", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold)).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .bearGlassCard(tint: BearTheme.accent(scheme), cornerRadius: 22)
                }.buttonStyle(BearPressStyle()).accessibilityIdentifier("relay-add-entry")
            }
        }.foregroundStyle(BearTheme.text(scheme)).padding(.top, 12)
    }
}

struct RelayBalanceCard: View {
    let state: RelayState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bearReduceMotion) private var reduceMotion
    private var presentation: RelayPresentation { RelayPresentation(state: state, at: Date()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "wallet.bifold").symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? nil : state.snapshot?.balances)
                    Text(state.account.displayName)
                }.font(.headline)
                Spacer(minLength: 6)
                Text("APIKEY.FAN").font(.caption2.weight(.semibold)).foregroundStyle(BearTheme.secondaryText(scheme))
            }
            Text(presentation.headline).font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5).privacySensitive()
                .contentTransition(.numericText()).accessibilityLabel(presentation.fullValue)
            HStack {
                Text(presentation.status)
                Spacer(minLength: 4)
                if let snapshot = state.snapshot { Text(snapshot.fetchedAt, style: .time) }
                Image(systemName: "arrow.up.right")
            }.font(.caption).foregroundStyle(presentation.isStale ? BearTheme.warning(scheme) : BearTheme.secondaryText(scheme))
        }.foregroundStyle(BearTheme.text(scheme)).padding(20)
            .bearGlassCard(tint: BearTheme.accent(scheme), cornerRadius: 26)
            .accessibilityElement(children: .combine)
            .animation(reduceMotion ? BearMotion.quiet : BearMotion.data, value: state.snapshot?.balances)
    }
}

public struct RelayAccountsView: View {
    @Bindable private var model: RelayModel
    @State private var adding = false
    public init(model: RelayModel) { self.model = model }
    public var body: some View {
        List {
            Section {
                ForEach(model.states) { state in
                    NavigationLink { RelayDetail(id: state.id, model: model) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(state.account.displayName).font(.headline)
                            Text(RelayPresentation(state: state, at: Date()).headline).font(.subheadline).privacySensitive()
                        }
                    }.accessibilityIdentifier("relay-list-" + state.id.uuidString)
                }
                Button { adding = true } label: { Label("添加账户", systemImage: "plus") }
                    .disabled(model.saving || model.clearing).accessibilityIdentifier("relay-add")
            } header: { Text("APIKEY.FAN") } footer: {
                Text("仅支持已审核模板。Key 只保存在手机共享钥匙串；只读余额，不发模型请求，不保存网页 Cookie。")
            }
        }
        .navigationTitle("中转账户")
        .task { await model.load() }
        .sheet(isPresented: $adding) { RelayEditor(model: model, account: nil) }
    }
}

struct RelayDetail: View {
    let id: UUID
    @Bindable var model: RelayModel
    @State private var editing = false
    @State private var deleting = false
    @State private var success = 0
    @State private var failure = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.bearReduceMotion) private var reduceMotion
    private var state: RelayState? { model.states.first { $0.id == id } }
    var body: some View {
        ScrollView {
            if let state {
                VStack(alignment: .leading, spacing: 22) {
                    RelayBalanceCard(state: state)
                    if let failure = state.failure {
                        Label(AIUsageModel.explanation(failure), systemImage: "exclamationmark.circle")
                            .foregroundStyle(BearTheme.warning(scheme))
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("查询接口", value: state.account.endpoint.path)
                        Text(RelayPresentation(state: state, at: Date()).availability)
                        if let snapshot = state.snapshot {
                            Text("数据时间：" + snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))
                        }
                        if let feedback = model.feedback[id] { Text(feedback).modifier(BearVerifiedFlash(trigger: feedback)) }
                    }.font(.subheadline).foregroundStyle(BearTheme.secondaryText(scheme))
                    Text("余额单位以该接口返回为准。零余额与负余额均保留；服务未提供状态时不推测可用性。")
                        .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
                }.padding(20)
            } else {
                ContentUnavailableView("账户已移除", systemImage: "network.slash", description: Text("可返回中转账户重新添加。"))
            }
        }
        .background(BearTheme.paper(scheme).ignoresSafeArea())
        .navigationTitle(state?.account.displayName ?? "中转账户")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button { Task { _ = await refresh() } } label: {
                        BearRefreshGlyph(refreshing: model.refreshing.contains(id), success: success, failure: failure)
                    }.disabled(state == nil || model.refreshing.contains(id) || model.saving)
                        .accessibilityLabel("刷新中转余额").accessibilityIdentifier("relay-refresh")
                    Menu {
                        Button("编辑账户") { editing = true }.disabled(model.saving)
                        Button("删除账户", role: .destructive) { deleting = true }.disabled(model.saving)
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("中转账户操作")
                }
            }
        }
        .bearPullToRefresh(enabled: state != nil && !model.refreshing.contains(id) && !model.saving) { await refresh() }
        .sensoryFeedback(.success, trigger: success).sensoryFeedback(.warning, trigger: failure)
        .animation(reduceMotion ? BearMotion.quiet : BearMotion.data, value: state?.snapshot?.balances)
        .sheet(isPresented: $editing) { RelayEditor(model: model, account: state?.account) }
        .confirmationDialog("删除此账户及本机密钥和缓存？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除账户", role: .destructive) { Task { if await model.delete(id) { dismiss() } } }
        }
        .alert("暂未完成", isPresented: Binding(get: { !editing && model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .task { await model.load() }
    }
    private func refresh() async -> Bool {
        let result = await model.refresh(id, report: false)
        if result { success &+= 1 } else { failure &+= 1 }
        return result
    }
}

struct RelayEditor: View {
    @Bindable var model: RelayModel
    let account: RelayAccount?
    @State private var name = ""
    @State private var key = ""
    @State private var endpoint: RelayEndpoint = .balance
    @State private var task: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("已审核模板 · APIKEY.FAN") {
                    TextField("账户名称", text: $name).accessibilityIdentifier("relay-name")
                    Picker("余额接口", selection: $endpoint) {
                        Text("余额 · /user/balance（默认）").tag(RelayEndpoint.balance)
                        Text("用量 · /v1/usage").tag(RelayEndpoint.usage)
                    }.accessibilityIdentifier("relay-endpoint")
                    keyField.privacySensitive().autocorrectionDisabled().accessibilityIdentifier("relay-key")
                    if account != nil { Text("留空保留原密钥；不会回填或显示已保存的 Key。").font(.footnote) }
                }
                Section {
                    Text("只向 https://api.apikey.fan" + endpoint.path + " 发送 Bearer Key。拒绝重定向，不访问任何其他站点；先验证新配置，失败保留原账户。")
                        .font(.footnote)
                    Button(model.saving ? "正在验证…" : "验证并保存") {
                        let submitted = key
                        task = Task {
                            if await model.save(id: account?.id, name: name, endpoint: endpoint, key: submitted) { key = ""; dismiss() }
                        }
                    }.disabled(model.saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (account == nil && key.isEmpty))
                        .accessibilityIdentifier("relay-save")
                    if let message = model.message { Text(message).font(.footnote).accessibilityIdentifier("relay-error") }
                }
            }
            .navigationTitle(account == nil ? "添加中转账户" : "编辑中转账户")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { task?.cancel(); dismiss() } } }
            .onAppear { name = account?.displayName ?? "我的中转"; endpoint = account?.endpoint ?? .balance; model.message = nil }
            .onDisappear { task?.cancel(); key = "" }
        }
    }
    @ViewBuilder private var keyField: some View {
        #if os(iOS)
        SecureField(account == nil ? "API Key" : "新的 API Key（可留空）", text: $key).textInputAutocapitalization(.never)
        #else
        SecureField(account == nil ? "API Key" : "新的 API Key（可留空）", text: $key)
        #endif
    }
}
