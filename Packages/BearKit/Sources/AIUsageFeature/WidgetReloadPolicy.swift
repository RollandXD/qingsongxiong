import AIUsageDomain
import Foundation

/// 仅内容或账户身份变化才通知；时间戳由组件自身时间线负责，不消耗额外预算。
struct WidgetReloadPolicy {
    struct Signature: Equatable {
        let sessionID: UUID?
        let connection: AccountConnection?
        let windows: [QuotaWindow]?
        let balances: [CurrencyBalance]?
        let isAvailable: Bool?
        let failure: UsageFailure?

        init(_ state: ProviderState?) {
            sessionID = state?.sessionID
            connection = state?.connection
            windows = state?.snapshot?.windows
            balances = state?.snapshot?.balances
            isAvailable = state?.snapshot?.isAvailable
            failure = state?.failure
        }
    }

    private var published: [ProviderID: Signature]?

    mutating func seedIfNeeded(_ states: [ProviderID: ProviderState], at date: Date) {
        if published == nil { _ = shouldReload(states, at: date) }
    }

    /// 返回是否需要通知小组件；需要时同时记下本次推送的内容。
    mutating func shouldReload(_ states: [ProviderID: ProviderState], at date: Date, force: Bool = false) -> Bool {
        let current = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, Signature(states[$0])) })
        guard force || current != published else { return false }
        published = current
        return true
    }
}
