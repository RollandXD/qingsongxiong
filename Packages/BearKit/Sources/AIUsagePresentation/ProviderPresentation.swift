import AIUsageDomain
import Foundation

/// App 与 Widget 共用的展示规则，不包含页面、凭据或网络访问。
public enum ProviderPresentation {
    public static func paletteIndex(_ provider: ProviderID) -> Int {
        switch provider { case .codex: 0; case .claude: 1; case .deepseek: 2 }
    }
    public static func percent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }
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
        let windows = snapshot.windows.map { UsageWindowPresentation($0, provider: snapshot.provider) }
        let general = windows.filter { $0.role == .general }
        if let window = (general.isEmpty ? windows : general).min(by: { $0.remaining < $1.remaining }) {
            return "剩余 " + percent(window.remaining)
        }
        return "暂无读数"
    }
}
