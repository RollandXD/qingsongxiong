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

struct RelayAccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "中转账户")
    static let defaultQuery = RelayAccountQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ account: RelayAccount) { id = account.id.uuidString; name = account.displayName }
}
struct RelayAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RelayAccountEntity] {
        let values = await WidgetDependencies.relay?.cachedStates() ?? []
        return identifiers.compactMap { id in values.first(where: { $0.id.uuidString == id }).map { RelayAccountEntity($0.account) } }
    }
    func suggestedEntities() async throws -> [RelayAccountEntity] {
        await WidgetDependencies.relay?.cachedStates().map { RelayAccountEntity($0.account) } ?? []
    }
}
struct ProviderConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择平台或中转账户"
    static let description = IntentDescription("中转账户有独立余额，不与订阅额度合并；选中后优先展示该账户。")
    @Parameter(title: "平台", default: .codex) var provider: WidgetProviderChoice
    @Parameter(title: "中转账户（可选）") var relay: RelayAccountEntity?
}

enum WidgetDependencies {
    static let reader: WidgetUsageReader? = {
        let shared = SharedResources()
        guard let container = try? shared.containerURL(),
              let vault = try? shared.vault(service: "io.github.rollandxd.qingsongxiong.ai-usage") else { return nil }
        return WidgetUsageReader(credentials: SecureUsageCredentialStore(values: vault),
            states: FileUsageStateStore(container: container), fetchers: UsageAdapterRegistry.make(client: URLSessionHTTPClient()))
    }()
    static let relay: WidgetRelayReader? = {
        let shared = SharedResources()
        guard let container = try? shared.containerURL(), let store = try? FileRelayStore(container: container),
              let vault = try? shared.vault(service: "io.github.rollandxd.qingsongxiong.ai-usage.relay") else { return nil }
        return WidgetRelayReader(store: store, credentials: SecureRelayCredentials(values: vault),
            adapter: RelayBalanceAdapter(client: URLSessionHTTPClient(followRedirects: false)))
    }()
}

struct UsageEntry: TimelineEntry, Sendable {
    let date: Date
    let states: [ProviderState]
    let provider: ProviderID?
    let preview: Bool
    var relays: [RelayState] = []
    var relayID: UUID?
}

private func usageTimeline(_ entry: UsageEntry) -> Timeline<UsageEntry> {
    let refreshAt = entry.date.addingTimeInterval(900)
    // 条目推进「旧读数」状态；日期只来自快照，不伪造新读数。
    let expiryDates = Set(entry.states.compactMap { $0.snapshot?.fetchedAt.addingTimeInterval(900) }
        + entry.relays.compactMap { $0.snapshot?.fetchedAt.addingTimeInterval(900) })
        .filter { $0 > entry.date && $0 <= refreshAt }.sorted()
    let entries = [entry] + expiryDates.map { date in var next = entry; next = UsageEntry(date: date,
        states: entry.states, provider: entry.provider, preview: entry.preview, relays: entry.relays, relayID: entry.relayID); return next }
    return Timeline(entries: entries, policy: .after(refreshAt))
}

private func usageEntry(provider: ProviderID? = nil, relayID: UUID? = nil, preview: Bool = false, refresh: Bool = false) async -> UsageEntry {
    if let relayID {
        let state = preview ? nil : await WidgetDependencies.relay?.state(relayID, refresh: refresh)
        return UsageEntry(date: Date(), states: [], provider: nil, preview: preview, relays: state.map { [$0] } ?? [], relayID: relayID)
    }
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
    else { states = providers.map { ProviderState(provider: $0, sessionID: nil, connection: .unknown, snapshot: nil, failure: .unavailable, updatedAt: Date()) } }
    var relays: [RelayState] = []
    if provider == nil, !preview, let reader = WidgetDependencies.relay {
        let cached = await reader.cachedStates()
        for state in cached.prefix(3) { if let value = await reader.state(state.id, refresh: refresh) { relays.append(value) } }
    }
    return UsageEntry(date: Date(), states: states, provider: provider, preview: preview, relays: relays)
}

struct OverviewTimeline: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: Date(), states: ProviderID.allCases.map { .disconnected($0, at: Date()) }, provider: nil, preview: true) }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (UsageEntry) -> Void) {
        let preview = context.isPreview; Task { completion(await usageEntry(preview: preview)) }
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<UsageEntry>) -> Void) {
        Task { completion(usageTimeline(await usageEntry(refresh: true))) }
    }
}
struct ProviderTimeline: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: Date(), states: [.disconnected(.codex, at: Date())], provider: .codex, preview: true) }
    func snapshot(for configuration: ProviderConfiguration, in context: Context) async -> UsageEntry {
        await usageEntry(provider: configuration.provider.provider, relayID: configuration.relay.flatMap { UUID(uuidString: $0.id) }, preview: context.isPreview)
    }
    func timeline(for configuration: ProviderConfiguration, in context: Context) async -> Timeline<UsageEntry> {
        usageTimeline(await usageEntry(provider: configuration.provider.provider, relayID: configuration.relay.flatMap { UUID(uuidString: $0.id) }, refresh: true))
    }
}

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    private var refreshControl: AnyView {
        AnyView(Button(intent: RefreshUsageIntent(provider: entry.provider, relayID: entry.relayID)) {
            Image(systemName: "arrow.clockwise").font(.caption).padding(5)
        }.buttonStyle(.plain).invalidatableContent().accessibilityLabel("刷新额度"))
    }
    var body: some View {
        Group {
            if let id = entry.relayID {
                RelayWidgetMetric(state: entry.relays.first, date: entry.date, family: family, refreshControl: refreshControl)
                    .widgetURL(RelayPresentation.url(id))
            } else {
                WidgetMetricContent(states: entry.states, provider: entry.provider, date: entry.date,
                    family: family, relays: entry.relays, refreshControl: refreshControl)
                    .widgetURL(URL(string: "qingsongxiong://ai-usage/provider/" + (entry.provider?.rawValue ?? "codex")))
            }
        }.containerBackground(for: .widget) {
            BearTheme.paper(scheme)
        }
    }
}
struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QingSongXiong.Overview", provider: OverviewTimeline()) { UsageWidgetView(entry: $0) }
            .configurationDisplayName("轻松熊 · 总览").description("三家平台额度与中转余额，各自清楚。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct SingleProviderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QingSongXiong.Provider", intent: ProviderConfiguration.self, provider: ProviderTimeline()) { UsageWidgetView(entry: $0) }
            .configurationDisplayName("轻松熊 · 单平台或中转").description("选择平台或独立中转账户，支持锁屏与手动刷新。")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
@main struct QingSongXiongWidgetBundle: WidgetBundle {
    var body: some Widget { OverviewWidget(); SingleProviderWidget() }
}
