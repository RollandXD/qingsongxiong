import AIUsageDomain
import Foundation

/// 小组件刷新节流：读数变化立即推送；读数不变时最多每 `freshnessInterval` 推一次，
/// 让小组件的「更新于」和过期判定（fetchedAt + 15 分钟）不至于误报。
struct WidgetReloadPolicy {
    struct Signature: Equatable {
        let connection: AccountConnection?
        let windows: [QuotaWindow]?
        let balances: [CurrencyBalance]?
        let isAvailable: Bool?
        let failure: UsageFailure?

        init(_ state: ProviderState?) {
            connection = state?.connection
            windows = state?.snapshot?.windows
            balances = state?.snapshot?.balances
            isAvailable = state?.snapshot?.isAvailable
            failure = state?.failure
        }
    }

    var freshnessInterval: TimeInterval = 600
    private var published: [ProviderID: Signature]?
    private var publishedAt: Date?

    /// 返回是否需要通知小组件；需要时同时记下本次推送的内容。
    mutating func shouldReload(_ states: [ProviderID: ProviderState], at date: Date, force: Bool = false) -> Bool {
        let current = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, Signature(states[$0])) })
        let stale = publishedAt.map { date.timeIntervalSince($0) >= freshnessInterval } ?? true
        guard force || current != published || stale else { return false }
        published = current
        publishedAt = date
        return true
    }
}
