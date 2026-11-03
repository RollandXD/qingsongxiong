import AIUsageData
import AIUsageAuth
import AIUsageFeature
import AIUsageDomain
import BearDesignSystem
import BearFoundation
import BearPlatform
import Foundation
import SwiftUI
import WidgetKit

#if DEBUG && targetEnvironment(simulator)
/// 自动化 UI 测试不依赖模拟器的签名/钥匙串权限，不使用真实账户。
private final class UITestSecureValues: SecureValueStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read(key: String) throws -> Data? { lock.withLock { values[key] } }
    func write(_ data: Data, key: String) throws { lock.withLock { values[key] = data } }
    func remove(key: String) throws { lock.withLock { values[key] = nil } }
}
#endif

@main
struct QingSongXiongApp: App {
    var body: some Scene { WindowGroup { AppRoot() } }
}

@MainActor
struct AppFeatureEntry {
    let descriptor: FeatureDescriptor
    let home: AnyView
    let settings: AnyView
    let clearLocalData: @MainActor () async -> Bool
    let handle: ([String]) -> Bool
}

@MainActor @Observable
private final class AppComposition {
    let entries: [AppFeatureEntry]
    let catalog: FeatureCatalog

    init() {
        let navigation = AIUsageNavigation()
        let model: AIUsageModel
        do {
            let shared = SharedResources()
            let states = FileUsageStateStore(container: try shared.containerURL())
            let values: any SecureValueStore
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") { values = UITestSecureValues() }
            else { values = try shared.vault(service: "io.github.rollandxd.qingsongxiong.ai-usage") }
            #else
            values = try shared.vault(service: "io.github.rollandxd.qingsongxiong.ai-usage")
            #endif
            let credentials = SecureUsageCredentialStore(values: values)
            let client = URLSessionHTTPClient()
            let tokenClient = OAuthTokenClient(client: client)
            let repository = LiveAIUsageRepository(credentials: credentials, states: states,
                fetchers: UsageAdapterRegistry.make(client: client), renewer: tokenClient)
            let connector = MobileAccountConnector(repository: repository, tokenClient: tokenClient,
                                                    browser: SystemOAuthBrowser())
            model = AIUsageModel(repository: repository, connector: connector,
                                 onDataChange: { WidgetCenter.shared.reloadAllTimelines() })
        } catch {
            model = AIUsageModel(repository: VerificationGatedRepository(), connector: nil)
            model.message = "共享存储不可用，请在设置中检查 App 与小组件共享能力。"
        }
        var entries = [AppFeatureEntry(
            descriptor: FeatureDescriptor(id: "ai-usage", title: "AI 额度", systemImage: "sparkles"),
            home: AnyView(AIUsageHome(model: model, navigation: navigation)),
            settings: AnyView(AIUsageAccountSettings(model: model)),
            clearLocalData: { await model.clearLocalData() },
            handle: { navigation.handle(components: $0) }
        )]
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--counter-proof") {
            entries.append(AppFeatureEntry(
                descriptor: FeatureDescriptor(id: "local-counter", title: "计数验证", systemImage: "plus.circle"),
                home: AnyView(DevelopmentCounter()), settings: AnyView(EmptyView()),
                clearLocalData: { true }, handle: { _ in false }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                SettingsScreen(appearance: $appearance, entries: composition.entries)
            }
        }
        .tint(BearTheme.accent(colorScheme))
        .preferredColorScheme(preferredScheme)
        .environment(\.dynamicTypeSize, usesLargeTypeFixture ? .accessibility3 : dynamicTypeSize)
        .onOpenURL { url in selectedTab = "home"; composition.open(url) }
    }

    private var usesLargeTypeFixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--ui-large-type")
        #else
        false
        #endif
    }
}

private struct SettingsScreen: View {
    @Binding var appearance: String
    let entries: [AppFeatureEntry]
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
                    Text("可检查 App 与小组件的共享权限和数据保留。")
                        .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
                }
                Section("功能账户") {
                    ForEach(entries, id: \.descriptor.id) { entry in entry.settings }
                }
                Section("隐私") {
                    NavigationLink("隐私与清除数据") { PrivacyScreen(entries: entries) }
                        .accessibilityIdentifier("open-privacy")
                }
                Section("关于") {
                    LabeledContent("轻松熊", value: version)
                    Text("个人工具箱 · 原生 SwiftUI 与 WidgetKit")
                    Text("凭据仅用于对应平台官方请求，保存在手机钥匙串；不发送模型请求。")
                        .font(.footnote).foregroundStyle(BearTheme.secondaryText(scheme))
                    NavigationLink("开源许可与来源") { OpenSourceScreen() }
                    Link("查看项目源码", destination: URL(string: "https://github.com/RollandXD/qingsongxiong")!)
                }
            }
            .scrollContentBackground(.hidden)
            .background(BearTheme.background(scheme))
            .navigationTitle("设置")
        }
    }

    private var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return marketing + " (" + build + ") · 接入预览"
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
