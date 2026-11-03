import AIUsageData
import AIUsageDomain
import AIUsagePresentation
import AppIntents
import BearDesignSystem
import BearPlatform
import SwiftUI
import WidgetKit

enum WidgetProviderChoice: String, AppEnum {
    case codex, claude, deepseek
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "平台")
    static let caseDisplayRepresentations: [WidgetProviderChoice: DisplayRepresentation] = [
        .codex: "Codex", .claude: "Claude", .deepseek: "DeepSeek",
    ]
    var provider: ProviderID { switch self { case .codex: .codex; case .claude: .claude; case .deepseek: .deepseek } }
}

struct ProviderConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择平台"
    static let description = IntentDescription("选择要在主屏幕查看的平台。")
    @Parameter(title: "平台", default: .codex) var provider: WidgetProviderChoice
}

private enum WidgetDependencies {
    static let reader: WidgetUsageReader? = {
        let shared = SharedResources()
        guard let container = try? shared.containerURL(),
              let vault = try? shared.vault(service: "io.github.rollandxd.qingsongxiong.ai-usage") else { return nil }
        return WidgetUsageReader(credentials: SecureUsageCredentialStore(values: vault),
                                 states: FileUsageStateStore(container: container),
                                 fetchers: [.deepseek: DeepSeekAdapter(client: URLSessionHTTPClient())])
    }()
}

struct UsageEntry: TimelineEntry, Sendable {
    let date: Date
    let states: [ProviderState]
    let provider: ProviderID?
    let preview: Bool
}

private func usageTimeline(_ entry: UsageEntry) -> Timeline<UsageEntry> {
    let refreshAt = entry.date.addingTimeInterval(1800)
    let expiryDates = Set(entry.states.compactMap { $0.snapshot?.fetchedAt.addingTimeInterval(900) })
        .filter { $0 > entry.date && $0 <= refreshAt }.sorted()
    let entries = [entry] + expiryDates.map {
        UsageEntry(date: $0, states: entry.states, provider: entry.provider, preview: entry.preview)
    }
    return Timeline(entries: entries, policy: .after(refreshAt))
}

private func usageEntry(provider: ProviderID? = nil, preview: Bool = false, refresh: Bool = false) async -> UsageEntry {
    let providers = provider.map { [$0] } ?? ProviderID.allCases
    let states: [ProviderState]
    if !preview, let reader = WidgetDependencies.reader {
        states = await withTaskGroup(of: ProviderState.self) { group in
            for id in providers { group.addTask { await reader.state(for: id, refresh: refresh) } }
            var results: [ProviderState] = []
            for await state in group { results.append(state) }
            return providers.compactMap { id in results.first { $0.provider == id } }
        }
    } else if preview { states = providers.map { .disconnected($0, at: Date()) } }
    else {
        states = providers.map {
            ProviderState(provider: $0, sessionID: nil, connection: .unknown,
                          snapshot: nil, failure: .unavailable, updatedAt: Date())
        }
    }
    return UsageEntry(date: Date(), states: states, provider: provider, preview: preview)
}

struct OverviewTimeline: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), states: ProviderID.allCases.map { .disconnected($0, at: Date()) }, provider: nil, preview: true)
    }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (UsageEntry) -> Void) {
        let preview = context.isPreview
        Task { completion(await usageEntry(preview: preview)) }
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<UsageEntry>) -> Void) {
        Task { completion(usageTimeline(await usageEntry(refresh: true))) }
    }
}

struct ProviderTimeline: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), states: [.disconnected(.codex, at: Date())], provider: .codex, preview: true)
    }
    func snapshot(for configuration: ProviderConfiguration, in context: Context) async -> UsageEntry {
        await usageEntry(provider: configuration.provider.provider, preview: context.isPreview)
    }
    func timeline(for configuration: ProviderConfiguration, in context: Context) async -> Timeline<UsageEntry> {
        usageTimeline(await usageEntry(provider: configuration.provider.provider, refresh: true))
    }
}

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack(spacing: 7) {
                BearMark().frame(width: 24, height: 24).widgetAccentable().accessibilityHidden(true)
                Text(entry.provider.map(ProviderPresentation.name) ?? "轻松熊").font(.headline)
                if entry.preview { Text("预览").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            ForEach(entry.states, id: \.provider) { state in
                Link(destination: URL(string: "qingsongxiong://ai-usage/provider/" + state.provider.rawValue)!) {
                    stateView(state)
                }
            }
            if family == .systemLarge {
                Spacer(minLength: 0)
                Text("读取时间分别显示 · 点击查看详情").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { BearTheme.background(scheme) }
        .widgetURL(URL(string: "qingsongxiong://ai-usage/provider/" + (entry.provider?.rawValue ?? "codex")))
    }

    @ViewBuilder private func stateView(_ state: ProviderState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if entry.provider == nil {
                HStack {
                    Text(ProviderPresentation.name(state.provider)).font(.subheadline.bold())
                    Spacer(minLength: 3)
                    Text(ProviderPresentation.headline(state.snapshot)).font(.subheadline.monospacedDigit())
                }
            } else {
                Text(ProviderPresentation.headline(state.snapshot))
                    .font(.system(family == .systemSmall ? .title3 : .title2, design: .rounded).bold())
                    .monospacedDigit().lineLimit(2).minimumScaleFactor(0.75)
            }
            HStack(spacing: 4) {
                Text(status(state))
                if let snapshot = state.snapshot { Text(snapshot.fetchedAt, style: .time) }
            }.font(.caption2).foregroundStyle(.secondary)
            if family == .systemLarge || (entry.provider != nil && family == .systemMedium) {
                if let snapshot = state.snapshot {
                    ForEach(snapshot.windows.prefix(2), id: \.id) { window in
                        HStack {
                            Text(window.label)
                            Spacer(minLength: 2)
                            Text(window.usedPercent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                        }.font(.caption)
                    }
                }
            }
        }.privacySensitive().accessibilityElement(children: .combine)
    }

    private func status(_ state: ProviderState) -> String {
        if state.connection == .disconnected { return "尚未连接" }
        if state.connection == .unknown { return "暂不可读取 · 打开 App" }
        if state.connection == .reconnectRequired { return "需要重新连接" }
        if state.failure == .appRefreshRequired { return "打开 App 更新授权" }
        if state.snapshot == nil { return "等待读取" }
        return state.isStale(at: entry.date) ? "旧读数 ·" : "更新于"
    }
}

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QingSongXiong.Overview", provider: OverviewTimeline()) { UsageWidgetView(entry: $0) }
            .configurationDisplayName("轻松熊 · 总览").description("三家平台的额度与余额，各自清楚。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SingleProviderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QingSongXiong.Provider", intent: ProviderConfiguration.self,
                               provider: ProviderTimeline()) { UsageWidgetView(entry: $0) }
            .configurationDisplayName("轻松熊 · 单平台").description("选择一个平台，查看额度或余额。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct QingSongXiongWidgetBundle: WidgetBundle {
    var body: some Widget { OverviewWidget(); SingleProviderWidget() }
}
