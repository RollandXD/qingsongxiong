import AIUsageDomain
import Foundation
import Testing

@Test func invalidQuotaIsNotTreatedAsZero() throws {
    #expect(throws: QuotaWindow.ValidationError.invalidPercentage) {
        try QuotaWindow(id: "x", label: "x", usedPercent: .nan, resetsAt: nil)
    }
    let past = Date(timeIntervalSince1970: 0)
    let window = try QuotaWindow(id: "weekly", label: "周额度", usedPercent: 83, resetsAt: past)
    #expect(window.usedPercent == 83)
    #expect(window.remainingPercent == 17)
}

@Test func balanceRoundTripKeepsDecimalAndCurrency() throws {
    let amount = Decimal(string: "0.123456789012345678")!
    let snapshot = UsageSnapshot(provider: .deepseek, windows: [],
                                balances: [CurrencyBalance(currency: "CNY", total: amount)],
                                isAvailable: false, fetchedAt: Date(timeIntervalSince1970: 200))
    let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: JSONEncoder().encode(snapshot))
    #expect(decoded.balances.first?.total == amount)
    #expect(decoded.balances.first?.currency == "CNY")
    #expect(decoded.windows.isEmpty)
    #expect(decoded.isAvailable == false)
}

@Test func providerRoutesAreOwnedByFeature() {
    #expect(AIUsageRoute.provider(components: ["provider", "claude"]) == .claude)
    #expect(AIUsageRoute.provider(components: ["provider", "unknown"]) == nil)
    #expect(AIUsageRoute.provider(components: ["provider", "codex", "extra"]) == nil)
}
