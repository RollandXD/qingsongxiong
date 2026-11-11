import AIUsageDomain
import AIUsagePresentation
import Foundation

/// 卡片按数据语义分流，余额账户不能因“也是 provider”就被塞进百分比蜜罐。
/// 保持 Foundation-only，让主卡类型选择与账户生命周期能在本地快速回归。
enum HomeCardSource: Equatable {
    case provider(HoneyJarPresentation)
    case providerBalance(ProviderDashboardPresentation)
    case relay(RelayPresentation)
    case unconnected(ProviderID)

    static func resolve(_ ref: AccountRef?, states: [ProviderID: ProviderState],
                        relays: [RelayState], at now: Date) -> HomeCardSource? {
        guard let ref else { return nil }
        switch ref {
        case .provider(let provider):
            guard let state = states[provider], state.connection == .connected else {
                return .unconnected(provider)
            }
            let presentation = ProviderDashboardPresentation(provider: provider, state: state, at: now)
            return provider == .deepseek ? .providerBalance(presentation) : .provider(HoneyJarPresentation(presentation))
        case .relay(let id):
            guard let state = relays.first(where: { $0.id == id }) else { return nil }
            return .relay(RelayPresentation(state: state, at: now))
        }
    }

    var ref: AccountRef {
        switch self {
        case .provider(let jar): .provider(jar.provider)
        case .providerBalance(let presentation): .provider(presentation.provider)
        case .relay(let presentation): .relay(presentation.state.id)
        case .unconnected(let provider): .provider(provider)
        }
    }

    var isConnected: Bool {
        switch self {
        case .provider(let jar): jar.isConnected
        case .providerBalance(let presentation): presentation.state?.connection == .connected
        case .relay(let presentation): presentation.state.snapshot != nil
        case .unconnected: false
        }
    }
}
