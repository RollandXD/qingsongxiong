#if DEBUG && targetEnvironment(simulator)
import AIUsageData
import AIUsageDomain
import BearDesignSystem
import SwiftUI
import WidgetKit

struct WidgetDemoScreen: View {
    @State private var states: [ProviderState] = []
    @State private var relays: [RelayState] = []
    @AppStorage("bear.appearance") private var appearance = "system"
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview("总览 · 中号", family: .systemMedium, provider: nil, width: 338, height: 158)
                    preview("总览 · 大号", family: .systemLarge, provider: nil, width: 338, height: 354)
                    HStack(spacing: 18) {
                        preview("单平台 · 小号", family: .systemSmall, provider: .claude, width: 158, height: 158)
                        preview("余额 · 小号", family: .systemSmall, provider: .deepseek, width: 158, height: 158)
                    }
                    preview("单平台 · 中号", family: .systemMedium, provider: .codex, width: 338, height: 158)
                    preview("余额 · 中号", family: .systemMedium, provider: .deepseek, width: 338, height: 158)
                    HStack(alignment: .top, spacing: 18) {
                        preview("锁屏 · 圆形", family: .accessoryCircular, provider: .codex, width: 72, height: 72)
                        preview("锁屏 · 矩形", family: .accessoryRectangular, provider: .claude, width: 220, height: 72)
                    }
                    preview("锁屏 · 单行", family: .accessoryInline, provider: .codex, width: 338, height: 40)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("中转 · 小号").font(.caption)
                        RelayWidgetMetric(state: relays.first, date: Date(), family: .systemSmall, refreshControl: AnyView(staticRefresh))
                            .padding(16).frame(width: 158, height: 158)
                            .background(BearTheme.surface(scheme), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                }.padding(18)
            }.background(BearTheme.background(scheme))
                .navigationTitle("组件布局演示")
                .task {
                    states = await DemoUsageRepository().allStates()
                    relays = (try? await DemoRelayRepository().states()) ?? []
                }
        }.preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
    /// 真实组件里是 Button(intent:)；App 内演示只摆同样大小的图标，不触发任何刷新。
    private var staticRefresh: some View {
        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
            .foregroundStyle(BearTheme.accentInk(scheme))
            .frame(width: 24, height: 24)
            .background(BearTheme.track(scheme), in: Circle())
            .accessibilityHidden(true)
    }
    private func preview(_ title: String, family: WidgetFamily, provider: ProviderID?, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(BearTheme.secondaryText(scheme))
            WidgetMetricContent(states: provider.map { id in states.filter { $0.provider == id } } ?? states,
                                provider: provider, date: Date(), family: family, relays: provider == nil ? relays : [])
                .padding(family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline ? 0 : 16)
                .frame(width: width, height: height)
                .background(BearTheme.surface(scheme), in: RoundedRectangle(cornerRadius: family == .accessoryCircular ? 36 : 24, style: .continuous))
                .accessibilityIdentifier("widget-demo-" + (provider?.rawValue ?? "overview") + "-" + String(describing: family))
        }
    }
}
#endif
