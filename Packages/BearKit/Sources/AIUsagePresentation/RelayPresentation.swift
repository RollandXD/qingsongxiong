import AIUsageDomain
import Foundation

public struct RelayPresentation: Equatable, Sendable {
    public let state: RelayState
    public let isStale: Bool
    public var headline: String {
        guard let balance = state.snapshot?.balances.first else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        // 明确展示层的分币舍入；Foundation 在不同平台对小数位上限的处理并不完全一致。
        // 只影响 headline，fullValue 与存储中的 Decimal 保持原样。
        formatter.roundingIncrement = 0.01
        return balance.currency + " " + (formatter.string(from: NSDecimalNumber(decimal: balance.total)) ?? NSDecimalNumber(decimal: balance.total).stringValue)
    }
    public var fullValue: String {
        guard let balance = state.snapshot?.balances.first else { return "尚未取数" }
        return balance.currency + " " + NSDecimalNumber(decimal: balance.total).stringValue
    }
    public var status: String {
        if state.failure == .reconnectRequired { return "密钥需要更新" }
        if state.failure != nil { return "上次读数 · 刷新未完成" }
        if state.snapshot?.isAvailable == false { return "服务标记不可用" }
        if state.snapshot == nil { return "尚未取数" }
        return isStale ? "上次读数" : "已连接"
    }
    public var availability: String {
        switch state.snapshot?.isAvailable {
        case true: "服务端标记可用"
        case false: "服务端标记不可用"
        case nil: "服务端未提供可用状态"
        }
    }
    public init(state: RelayState, at date: Date) {
        self.state = state
        isStale = state.failure != nil || state.snapshot.map { date.timeIntervalSince($0.fetchedAt) >= 900 } ?? true
    }
    public static func url(_ id: UUID) -> URL { URL(string: "qingsongxiong://ai-usage/relay/" + id.uuidString)! }
}
