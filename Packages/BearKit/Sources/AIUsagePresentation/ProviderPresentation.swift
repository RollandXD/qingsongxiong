import AIUsageDomain
import Foundation

/// App 与 Widget 共用的展示规则，不包含页面、凭据或网络访问。
public enum ProviderPresentation {
    public static func name(_ provider: ProviderID) -> String {
        switch provider { case .codex: "Codex"; case .claude: "Claude"; case .deepseek: "DeepSeek" }
    }
    public static func symbol(_ provider: ProviderID) -> String {
        switch provider { case .codex: "terminal"; case .claude: "sun.max"; case .deepseek: "water.waves" }
    }
    public static func money(_ amount: Decimal, currency: String) -> String {
        currency + " " + NSDecimalNumber(decimal: amount).stringValue
    }
    public static func headline(_ snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "—" }
        if let balance = snapshot.balances.first { return money(balance.total, currency: balance.currency) }
        if let window = snapshot.windows.max(by: { $0.usedPercent < $1.usedPercent }) {
            return "已用 " + window.usedPercent.formatted(.number.precision(.fractionLength(0...1))) + "%"
        }
        return "暂无读数"
    }
}
