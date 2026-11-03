import AIUsageDomain
import AIUsagePresentation
import BearDesignSystem
import Foundation
import SwiftUI

@MainActor @Observable
public final class AIUsageNavigation {
    public var path: [ProviderID] = []
    public init() {}
    public func handle(components: [String]) -> Bool {
        guard let provider = AIUsageRoute.provider(components: components) else { return false }
        path = [provider]
        return true
    }
}

public struct AIUsageHome: View {
    @Bindable private var model: AIUsageModel
    @Bindable private var navigation: AIUsageNavigation
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    private let onDataChange: @MainActor () -> Void

    public init(model: AIUsageModel, navigation: AIUsageNavigation,
                onDataChange: @escaping @MainActor () -> Void = {}) {
        self.model = model
        self.navigation = navigation
        self.onDataChange = onDataChange
    }

    public var body: some View {
        NavigationStack(path: $navigation.path) {
            List {
                Section {
                    HStack(spacing: 20) {
                        BearMark().frame(width: 64, height: 64).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("给忙碌，留一点余量").font(.title3.bold())
                            Text("每个平台，各自清楚。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 12)
                }
                Section("AI 额度") {
                    ForEach(ProviderID.allCases) { provider in
                        NavigationLink(value: provider) {
                            ProviderSummary(provider: provider, state: model.states[provider],
                                            refreshing: model.refreshing.contains(provider))
                        }.accessibilityIdentifier("provider-" + provider.rawValue)
                    }
                }
                Section {
                    Label("额度和余额由手机直接读取，凭据仅保留在本机钥匙串。", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(BearTheme.background(scheme))
            .navigationTitle("轻松熊")
            .navigationDestination(for: ProviderID.self) { provider in
                ProviderDetail(provider: provider, model: model)
            }
            .refreshable {
                await withTaskGroup(of: Void.self) { group in
                    for provider in ProviderID.allCases where model.states[provider]?.connection == .connected {
                        group.addTask { await model.refresh(provider, reportFailure: false) }
                    }
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.loadCached()
            await model.refreshIfNeeded()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
                await model.refreshIfNeeded()
            }
        }
        .onChange(of: model.dataRevision) { _, _ in onDataChange() }
        .alert("暂未完成", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("好") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}

private struct ProviderSummary: View {
    let provider: ProviderID
    let state: ProviderState?
    let refreshing: Bool
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: ProviderPresentation.symbol(provider)).font(.title2).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(ProviderPresentation.name(provider)).font(.headline)
                if state == nil {
                    Text("读取本机状态…").font(.caption).foregroundStyle(.secondary)
                } else if state?.connection == .disconnected {
                    Text("尚未连接").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(ProviderPresentation.headline(state?.snapshot)).font(.title3.monospacedDigit().bold())
                    if state?.connection == .reconnectRequired {
                        Text("需要重新连接").font(.caption).foregroundStyle(.orange)
                    } else if let snapshot = state?.snapshot {
                        HStack(spacing: 4) {
                            Text(state?.isStale(at: Date()) == true ? "旧读数 ·" : "更新于")
                            Text(snapshot.fetchedAt, style: .relative)
                        }.font(.caption).foregroundStyle(.secondary)
                    } else { Text("等待首次刷新").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Spacer(minLength: 4)
            if refreshing { ProgressView().accessibilityLabel("正在刷新") }
        }.padding(.vertical, 7).accessibilityElement(children: .combine)
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

private struct ProviderDetail: View {
    let provider: ProviderID
    @Bindable var model: AIUsageModel
    @State private var showKeyEntry = false
    @State private var confirmDisconnect = false
    @Environment(\.colorScheme) private var scheme
    private var state: ProviderState? { model.states[provider] }

    var body: some View {
        List {
            Section {
                ProviderSummary(provider: provider, state: state, refreshing: model.refreshing.contains(provider))
                if let failure = state?.failure {
                    Label(AIUsageModel.explanation(failure), systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let snapshot = state?.snapshot {
                if !snapshot.windows.isEmpty {
                    Section("使用窗口") {
                        ForEach(snapshot.windows, id: \.id) { window in QuotaWindowRow(window: window) }
                    }
                }
                if !snapshot.balances.isEmpty {
                    Section("余额") {
                        ForEach(Array(snapshot.balances.enumerated()), id: \.offset) { _, balance in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ProviderPresentation.money(balance.total, currency: balance.currency))
                                    .font(.title2.monospacedDigit().bold()).textSelection(.enabled)
                                if let grant = balance.granted {
                                    LabeledContent("赠送", value: ProviderPresentation.money(grant, currency: balance.currency))
                                }
                                if let topUp = balance.toppedUp {
                                    LabeledContent("充值", value: ProviderPresentation.money(topUp, currency: balance.currency))
                                }
                            }.padding(.vertical, 8)
                        }
                        if let available = snapshot.isAvailable {
                            Label((state?.isStale(at: Date()) == true ? "上次读取：" : "")
                                  + (available ? "余额可继续调用" : "余额不足以继续调用"),
                                  systemImage: available ? "checkmark.circle" : "exclamationmark.circle")
                        }
                    }
                }
                Section("数据时间") {
                    Text(snapshot.fetchedAt.formatted(date: .abbreviated, time: .standard))
                    if state?.isStale(at: Date()) == true { Text("当前显示上次成功读取的数据。").foregroundStyle(.secondary) }
                }.font(.footnote)
            }
            Section("账户") {
                if model.canConnect(provider) {
                    Button(state?.connection == .connected ? "更换账户" : "连接账户") {
                        if provider == .deepseek { showKeyEntry = true }
                        else { Task { await model.connect(provider, key: nil) } }
                    }
                    .disabled(model.connecting.contains(provider))
                    .accessibilityIdentifier("connect-" + provider.rawValue)
                } else {
                    Text("此平台的账户连接将在后续版本提供。").foregroundStyle(.secondary)
                }
                if let state, state.connection != .disconnected {
                    Button("刷新数据") { Task { await model.refresh(provider) } }
                        .disabled(model.refreshing.contains(provider) || model.connecting.contains(provider))
                    Button("退出账户", role: .destructive) { confirmDisconnect = true }
                }
            }
            if provider == .deepseek {
                Section { Text("连接的是 DeepSeek 官方 API 余额，与聊天 App 的会员或次数分开计算。").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BearTheme.background(scheme))
        .navigationTitle(ProviderPresentation.name(provider))
        .sheet(isPresented: $showKeyEntry) { APIKeySheet(model: model) }
        .confirmationDialog("退出后会清除本机凭据和该平台缓存。", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("退出账户", role: .destructive) { Task { await model.disconnect(provider) } }
        }
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(window.label, value: "已用 " + window.usedPercent.formatted(.number.precision(.fractionLength(0...1))) + "%")
            ProgressView(value: min(100, window.usedPercent), total: 100)
                .accessibilityLabel(window.label).accessibilityValue("已用 \(window.usedPercent.formatted())%")
            if let reset = window.resetsAt {
                Text(reset <= Date() ? "重置时间已过，等待刷新确认" : "重置于 " + reset.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
}

private struct APIKeySheet: View {
    @Bindable var model: AIUsageModel
    @State private var key = ""
    @State private var request: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    keyField.autocorrectionDisabled()
                        .privacySensitive().accessibilityIdentifier("deepseek-api-key")
                    Text("仅向 DeepSeek 官方余额接口验证，保存于手机钥匙串。").font(.footnote).foregroundStyle(.secondary)
                    Link("打开 DeepSeek 密钥管理", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                }
                Section {
                    Button(model.connecting.contains(.deepseek) ? "正在连接…" : "连接并读取余额") {
                        let submitted = key
                        request = Task { if await model.connect(.deepseek, key: submitted) { key = ""; dismiss() } }
                    }.disabled(key.isEmpty || model.connecting.contains(.deepseek))
                }
                if let message = model.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("连接 DeepSeek")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { request?.cancel(); dismiss() } } }
        }
        .onDisappear { request?.cancel(); key = "" }
    }

    @ViewBuilder private var keyField: some View {
        #if os(iOS)
        SecureField("DeepSeek API Key", text: $key).textInputAutocapitalization(.never)
        #else
        SecureField("DeepSeek API Key", text: $key)
        #endif
    }
}
