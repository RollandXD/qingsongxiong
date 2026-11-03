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
                                 fetchers: UsageAdapterRegistry.make(client: URLSessionHTTPClient()))
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
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        WidgetMetricContent(states: entry.states, provider: entry.provider, date: entry.date, family: family)
            .containerBackground(for: .widget) { BearTheme.background(scheme) }
            .widgetURL(URL(string: "qingsongxiong://ai-usage/provider/" + (entry.provider?.rawValue ?? "codex")))
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
