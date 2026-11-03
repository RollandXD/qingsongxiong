import AIUsageDomain
import CoreFoundation
import Foundation

/// 纯解析，不读取凭据、写缓存或推断缺失窗口的额度。
public enum UsageResponseParser {
    private struct DeepSeekResponse: Decodable {
        let is_available: Bool?
        let balance_infos: [Balance]
        struct Balance: Decodable {
            let currency: String
            let total_balance: String
            let granted_balance: String?
            let topped_up_balance: String?
        }
    }

    public static func deepseek(_ data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        do {
            let response = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
            let balances = try response.balance_infos.map { balance in
                guard !balance.currency.isEmpty else { throw UsageFailure.invalidResponse }
                return CurrencyBalance(currency: balance.currency, total: try amount(balance.total_balance),
                                       granted: try balance.granted_balance.map(amount),
                                       toppedUp: try balance.topped_up_balance.map(amount))
            }
            return UsageSnapshot(provider: .deepseek, windows: [], balances: balances,
                                 isAvailable: response.is_available, fetchedAt: fetchedAt)
        } catch { throw UsageFailure.invalidResponse }
    }

    private static func amount(_ text: String) throws -> Decimal {
        guard text.range(of: #"\A[+-]?[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN else { throw UsageFailure.invalidResponse }
        return amount
    }

    public static func codex(_ data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        let root = try object(data)
        var windows: [QuotaWindow] = []
        for (key, label) in [("rate_limit", ""), ("code_review_rate_limit", "代码审查")] {
            guard let limits = root[key] as? [String: Any] else { continue }
            for name in ["primary_window", "secondary_window"] {
                guard let raw = limits[name] as? [String: Any] else { continue }
                guard let used = number(raw["used_percent"]) else { throw UsageFailure.invalidResponse }
                let duration = number(raw["limit_window_seconds"])
                let title = label.isEmpty ? durationLabel(duration) : label + " · " + durationLabel(duration)
                let reset = date(raw["reset_at"]) ?? number(raw["reset_after_seconds"])
                    .map { fetchedAt.addingTimeInterval(max(0, $0)) }
                windows.append(try quota(id: key + "." + name, label: title, used: used, reset: reset))
            }
        }
        guard !windows.isEmpty else { throw UsageFailure.invalidResponse }
        return UsageSnapshot(provider: .codex, windows: windows, balances: [],
                             isAvailable: nil, fetchedAt: fetchedAt)
    }

    public static func claude(_ data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        let root = try object(data)
        var windows: [QuotaWindow] = []
        let fields = [("five_hour", "5 小时"), ("seven_day", "7 天 · 全部模型"),
                      ("seven_day_opus", "7 天 · Opus"), ("seven_day_sonnet", "7 天 · Sonnet")]
        for (key, label) in fields {
            guard let raw = root[key] as? [String: Any] else { continue }
            guard let used = number(raw["utilization"]) ?? number(raw["percent"]) else {
                throw UsageFailure.invalidResponse
            }
            windows.append(try quota(id: key, label: label, used: used, reset: date(raw["resets_at"])))
        }
        guard !windows.isEmpty else { throw UsageFailure.invalidResponse }
        return UsageSnapshot(provider: .claude, windows: windows, balances: [],
                             isAvailable: nil, fetchedAt: fetchedAt)
    }

    private static func quota(id: String, label: String, used: Double, reset: Date?) throws -> QuotaWindow {
        do { return try QuotaWindow(id: id, label: label, usedPercent: used, resetsAt: reset) }
        catch { throw UsageFailure.invalidResponse }
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageFailure.invalidResponse
        }
        return result
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func date(_ value: Any?) -> Date? {
        if let epoch = number(value) { return epoch > 0 ? Date(timeIntervalSince1970: epoch) : nil }
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func durationLabel(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0, seconds < Double(Int.max) else { return "额度窗口" }
        if seconds.truncatingRemainder(dividingBy: 86_400) == 0 { return "\(Int(seconds / 86_400)) 天" }
        if seconds.truncatingRemainder(dividingBy: 3_600) == 0 { return "\(Int(seconds / 3_600)) 小时" }
        return "\(Int(seconds / 60)) 分钟"
    }
}
