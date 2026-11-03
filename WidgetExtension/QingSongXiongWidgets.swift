import AIUsageDomain
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
    var title: String { switch self { case .codex: "Codex"; case .claude: "Claude"; case .deepseek: "DeepSeek" } }
}

struct ProviderConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择平台"
    static let description = IntentDescription("验证单平台组件的配置与页面跳转。")
    @Parameter(title: "平台", default: .codex) var provider: WidgetProviderChoice
}

struct ProbeEntry: TimelineEntry {
    let date: Date
    let report: ProbeReport
    let provider: WidgetProviderChoice?
    let preview: Bool
}

private func entry(provider: WidgetProviderChoice? = nil, preview: Bool = false) -> ProbeEntry {
    ProbeEntry(date: Date(), report: SigningProbe.configured().inspect(), provider: provider, preview: preview)
}

struct OverviewTimeline: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry { entry(preview: true) }
    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(entry(preview: context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct ProviderTimeline: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry { entry(provider: .codex, preview: true) }
    func snapshot(for configuration: ProviderConfiguration, in context: Context) async -> ProbeEntry {
        entry(provider: configuration.provider, preview: context.isPreview)
    }
    func timeline(for configuration: ProviderConfiguration, in context: Context) async -> Timeline<ProbeEntry> {
        Timeline(entries: [entry(provider: configuration.provider)], policy: .after(Date().addingTimeInterval(30 * 60)))
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 12) {
            HStack {
                BearMark().frame(width: 30, height: 30).widgetAccentable()
                Text(entry.provider?.title ?? "轻松熊").font(.headline)
                Spacer(minLength: 0)
            }
            Text(entry.preview ? "组件预览" : "安装验证")
                .font(.caption).foregroundStyle(.secondary)
            if let record = entry.report.record {
                Text("#\(record.revision)")
                    .font(.system(family == .systemSmall ? .title2 : .largeTitle, design: .rounded).bold())
                    .monospacedDigit()
                Label(entry.report.sharedKeychainReadable ? "钥匙串可读" : "钥匙串待验证",
                      systemImage: entry.report.sharedKeychainReadable ? "checkmark.shield" : "key")
                    .font(.caption)
                Text(record.updatedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("打开 App 写入验证数据").font(.subheadline)
                Text("尚未连接 AI 账户").font(.caption2).foregroundStyle(.secondary)
            }
            if family == .systemLarge {
                Divider()
                Text("组件编号应与 App 内一致。续签后请再次核对，确认共享数据仍然存在。")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { BearTheme.background(scheme) }
        .widgetURL(URL(string: "qingsongxiong://ai-usage/provider/" + (entry.provider?.rawValue ?? "codex")))
    }
}

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QingSongXiong.Overview", provider: OverviewTimeline()) { ProbeWidgetView(entry: $0) }
            .configurationDisplayName("轻松熊 · 总览")
            .description("验证主 App 与桌面组件共享数据。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct SingleProviderWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QingSongXiong.Provider", intent: ProviderConfiguration.self,
                               provider: ProviderTimeline()) { ProbeWidgetView(entry: $0) }
            .configurationDisplayName("轻松熊 · 单平台")
            .description("选择平台，验证配置与详情跳转。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct QingSongXiongWidgetBundle: WidgetBundle {
    var body: some Widget { OverviewWidget(); SingleProviderWidget() }
}
