import AIUsageData
import AIUsageFeature
import BearDesignSystem
import BearFoundation
import BearPlatform
import SwiftUI

@main
struct QingSongXiongApp: App {
    var body: some Scene { WindowGroup { AppRoot() } }
}

@MainActor
private struct AppFeatureEntry {
    let descriptor: FeatureDescriptor
    let home: AnyView
    let handle: ([String]) -> Bool
}

@MainActor @Observable
private final class AppComposition {
    let entries: [AppFeatureEntry]
    let catalog: FeatureCatalog

    init() {
        let navigation = AIUsageNavigation()
        var entries = [AppFeatureEntry(
            descriptor: FeatureDescriptor(id: "ai-usage", title: "AI 额度", systemImage: "sparkles"),
            home: AnyView(AIUsageHome(repository: VerificationGatedRepository(), navigation: navigation)),
            handle: { navigation.handle(components: $0) }
        )]
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--counter-proof") {
            entries.append(AppFeatureEntry(
                descriptor: FeatureDescriptor(id: "local-counter", title: "计数验证", systemImage: "plus.circle"),
                home: AnyView(DevelopmentCounter()), handle: { _ in false }
            ))
        }
        #endif
        self.entries = entries
        // 标识来自编译期注册；重复标识必须在开发期失败，而不是悄悄覆盖功能。
        catalog = try! FeatureCatalog(features: entries.map(\.descriptor))
    }

    func open(_ url: URL) {
        guard let route = catalog.route(for: url, scheme: "qingsongxiong"),
              let entry = entries.first(where: { $0.descriptor.id == route.featureID }) else { return }
        _ = entry.handle(route.components)
    }
}

private struct AppRoot: View {
    @State private var composition = AppComposition()
    @AppStorage("bear.appearance") private var appearance = "system"
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = "home"

    private var preferredScheme: ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("首页", systemImage: "house", value: "home") {
                if composition.entries.count == 1, let entry = composition.entries.first {
                    entry.home
                } else {
                    NavigationStack {
                        List(composition.entries, id: \.descriptor.id) { entry in
                            NavigationLink(entry.descriptor.title) { entry.home }
                        }.navigationTitle("轻松熊")
                    }
                }
            }
            Tab("设置", systemImage: "gearshape", value: "settings") {
                SettingsScreen(appearance: $appearance)
            }
        }
        .tint(BearTheme.accent(colorScheme))
        .preferredColorScheme(preferredScheme)
        .onOpenURL { url in selectedTab = "home"; composition.open(url) }
    }
}

private struct SettingsScreen: View {
    @Binding var appearance: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $appearance) {
                        Text("跟随系统").tag("system")
                        Text("奶油日光").tag("light")
                        Text("暖夜").tag("dark")
                    }
                }
                Section("安装验证") {
                    NavigationLink("检查 App 与小组件共享能力") { SigningVerificationScreen() }
                        .accessibilityIdentifier("open-signing-verification")
                    Text("请先完成这一步，再连接真实 AI 账户。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("关于") {
                    LabeledContent("轻松熊", value: "0.1 · 安装验证版")
                    Text("个人工具箱 · 原生 SwiftUI 与 WidgetKit")
                    Text("不上传账户信息，不包含模型调用。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(BearTheme.background(scheme))
            .navigationTitle("设置")
        }
    }
}

#if DEBUG
private struct DevelopmentCounter: View {
    @State private var count = 0
    var body: some View {
        VStack(spacing: 24) {
            Text("\(count)").font(.largeTitle.monospacedDigit()).accessibilityIdentifier("counter-value")
            Button("加一") { count += 1 }.accessibilityIdentifier("counter-increment")
        }.navigationTitle("计数验证")
    }
}
#endif
