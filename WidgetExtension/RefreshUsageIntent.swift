import AIUsageDomain
import AppIntents
import Foundation
import WidgetKit

/// 组件只用受限 Reader：不续期、不保存凭据、不写共享快照。
struct RefreshUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "刷新轻松熊额度"
    static let description = IntentDescription("读取当前额度；令牌过期时请打开轻松熊续期。")
    static let openAppWhenRun = false
    @Parameter(title: "平台标识") var providerID: String?
    @Parameter(title: "中转标识") var relayID: String?
    init() {}
    init(provider: ProviderID?, relayID: UUID?) { self.providerID = provider?.rawValue; self.relayID = relayID?.uuidString }
    func perform() async throws -> some IntentResult {
        if let text = relayID, let id = UUID(uuidString: text) {
            _ = await WidgetDependencies.relay?.state(id, refresh: true, force: true)
        } else {
            let providers = providerID.flatMap(ProviderID.init(rawValue:)).map { [$0] } ?? ProviderID.allCases
            if let reader = WidgetDependencies.reader {
                await withTaskGroup(of: Void.self) { group in
                    for id in providers { group.addTask { _ = await reader.state(for: id, refresh: true, force: true) } }
                }
            }
            if providerID == nil, let reader = WidgetDependencies.relay {
                for state in await reader.cachedStates().prefix(3) { _ = await reader.state(state.id, refresh: true, force: true) }
            }
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "QingSongXiong.Overview")
        WidgetCenter.shared.reloadTimelines(ofKind: "QingSongXiong.Provider")
        return .result()
    }
}
