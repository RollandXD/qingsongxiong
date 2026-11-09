import AIUsageDomain
import AIUsagePresentation
import Foundation
import Testing

@Test func relayPresentationKeepsNegativeAmountAndFullAccessiblePrecision() {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let account = RelayAccount(displayName: "合成账户")
    let snapshot = RelaySnapshot(balances: [CurrencyBalance(currency: "USD", total: Decimal(string: "-0.123456789")!)], isAvailable: nil, fetchedAt: date)
    let presentation = RelayPresentation(state: RelayState(account: account, snapshot: snapshot, updatedAt: date), at: date)
    #expect(presentation.headline.contains("-0.12"))
    #expect(presentation.fullValue == "USD -0.123456789")
    #expect(presentation.availability == "服务端未提供可用状态")
    #expect(!presentation.isStale)
    #expect(RelayPresentation(state: presentation.state, at: date.addingTimeInterval(900)).isStale)
}
@Test func relayMissingDataDoesNotLookLikeZeroAndExplicitFalseSurvives() {
    let date = Date()
    let account = RelayAccount(displayName: "合成账户")
    let missing = RelayPresentation(state: RelayState(account: account, snapshot: nil, updatedAt: date), at: date)
    #expect(missing.headline == "—")
    #expect(missing.status == "尚未取数")
    let snapshot = RelaySnapshot(balances: [CurrencyBalance(currency: "credits", total: 0)], isAvailable: false, fetchedAt: date)
    let value = RelayPresentation(state: RelayState(account: account, snapshot: snapshot, updatedAt: date), at: date)
    #expect(value.status == "服务标记不可用")
    #expect(value.headline.contains("0.00"))
}
