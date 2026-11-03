import AIUsageDomain
import BearDesignSystem
import SwiftUI

public enum ProviderPresentation {
    public static func name(_ provider: ProviderID) -> String {
        switch provider { case .codex: "Codex"; case .claude: "Claude"; case .deepseek: "DeepSeek" }
    }
    public static func symbol(_ provider: ProviderID) -> String {
        switch provider { case .codex: "terminal"; case .claude: "sun.max"; case .deepseek: "water.waves" }
    }
}

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
    private let repository: any AIUsageRepository
    @Bindable private var navigation: AIUsageNavigation
    @Environment(\.colorScheme) private var scheme

    public init(repository: any AIUsageRepository, navigation: AIUsageNavigation) {
        self.repository = repository
        self.navigation = navigation
    }

    public var body: some View {
        NavigationStack(path: $navigation.path) {
            List {
                Section {
                    HStack(spacing: 20) {
                        BearMark().frame(width: 74, height: 74)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("让余量，一目了然").font(.title3.bold())
                            Text("你的个人工具箱，从 AI 额度开始。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 12)
                }
                Section("AI 额度") {
                    ForEach(ProviderID.allCases) { provider in
                        NavigationLink(value: provider) {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ProviderPresentation.name(provider)).font(.headline)
                                    Text("等待完成手机安装验证").font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: ProviderPresentation.symbol(provider)) }
                        }.accessibilityIdentifier("provider-" + provider.rawValue)
                    }
                }
                Section {
                    Label("当前为安装验证版，尚未连接任何 AI 账户。", systemImage: "testtube.2")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(BearTheme.background(scheme))
            .navigationTitle("轻松熊")
            .navigationDestination(for: ProviderID.self) { provider in
                ProviderVerificationDetail(provider: provider, repository: repository)
            }
        }
    }
}

private struct ProviderVerificationDetail: View {
    let provider: ProviderID
    let repository: any AIUsageRepository
    @State private var message: String?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        List {
            Section {
                Label(ProviderPresentation.name(provider), systemImage: ProviderPresentation.symbol(provider))
                    .font(.title2.bold()).padding(.vertical)
                Text("先确认这个 App 和它的小组件能在你的手机上免费安装、共享数据和续签，再连接真实账户。")
                Button("检查当前接入状态") {
                    Task {
                        do { _ = try await repository.refresh(provider) }
                        catch { message = "安装验证尚未完成，真实数据接入保持关闭。" }
                    }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BearTheme.background(scheme))
        .navigationTitle(ProviderPresentation.name(provider))
    }
}
