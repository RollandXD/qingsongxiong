import AIUsageDomain
@testable import AIUsageFeature
import Foundation
import Testing

private let homeNow = Date(timeIntervalSince1970: 1_800_000_000)
private func homeState(_ provider: ProviderID, balances: [CurrencyBalance] = [],
                       connection: AccountConnection = .connected, snapshot: Bool = true) -> ProviderState {
    ProviderState(provider: provider, sessionID: UUID(), connection: connection,
                  snapshot: snapshot ? UsageSnapshot(provider: provider, windows: [], balances: balances,
                                                       isAvailable: true, fetchedAt: homeNow) : nil,
                  failure: nil, updatedAt: homeNow)
}

@Test func deepSeekHomeCardUsesMoneyNotAnEmptyHoneyJar() {
    let balance = CurrencyBalance(currency: "CNY", total: Decimal(string: "128.36")!)
    let source = HomeCardSource.resolve(.provider(.deepseek),
        states: [.deepseek: homeState(.deepseek, balances: [balance])], relays: [], at: homeNow)
    guard case .providerBalance(let presentation) = source else {
        Issue.record("DeepSeek 必须用金额主卡，不能走两只空蜜罐")
        return
    }
    #expect(presentation.balances.map(\.balance) == [balance])
    #expect(source?.ref == .provider(.deepseek))
    #expect(source?.isConnected == true)
}

@Test func quotaAccountsKeepTheirHoneyCardSemantics() {
    for provider in [ProviderID.codex, .claude] {
        let source = HomeCardSource.resolve(.provider(provider), states: [provider: homeState(provider)],
                                            relays: [], at: homeNow)
        guard case .provider(let jar) = source else { Issue.record("额度账户仍应使用蜜罐"); continue }
        #expect(jar.provider == provider)
        #expect(source?.ref == .provider(provider))
    }
}

@Test func twoBalanceCardsRetainSeparateReferencesCurrenciesAndValues() {
    let relay = RelayState(account: RelayAccount(displayName: "我的中转"),
        snapshot: RelaySnapshot(balances: [CurrencyBalance(currency: "USD", total: 42)],
                                isAvailable: true, fetchedAt: homeNow), updatedAt: homeNow)
    let balances = [CurrencyBalance(currency: "CNY", total: 128), CurrencyBalance(currency: "USD", total: 8)]
    let states = [ProviderID.deepseek: homeState(.deepseek, balances: balances)]
    let refs: [AccountRef] = [.provider(.deepseek), .relay(relay.id)]
    let cards = refs.compactMap { HomeCardSource.resolve($0, states: states, relays: [relay], at: homeNow) }
    #expect(cards.count == 2)
    #expect(cards.map(\.ref) == refs)
    guard case .providerBalance(let deepseek) = cards[0], case .relay(let transfer) = cards[1] else {
        Issue.record("两张余额卡都不应走额度百分比布局"); return
    }
    #expect(deepseek.balances.map(\.balance) == balances)
    #expect(transfer.state.snapshot?.balances.first?.total == 42)
    #expect(transfer.state.snapshot?.balances.first?.currency == "USD")
}

@Test func missingBalanceReadingsDoNotBecomeZeroOrAQuotaPercentage() {
    let source = HomeCardSource.resolve(.provider(.deepseek),
        states: [.deepseek: homeState(.deepseek, snapshot: false)], relays: [], at: homeNow)
    guard case .providerBalance(let presentation) = source else { Issue.record("仍应保留余额语义"); return }
    #expect(presentation.balances.isEmpty)
    #expect(presentation.headline == "—")
    #expect(presentation.status == "等待首次读取")
}

@Test func disconnectedProviderKeepsAConnectionEntryButDeletedRelayBecomesEmpty() {
    let provider = HomeCardSource.resolve(.provider(.deepseek),
        states: [.deepseek: homeState(.deepseek, connection: .disconnected)], relays: [], at: homeNow)
    #expect(provider == .unconnected(.deepseek))
    #expect(provider?.isConnected == false)
    #expect(HomeCardSource.resolve(.relay(UUID()), states: [:], relays: [], at: homeNow) == nil)
    #expect(HomeCardSource.resolve(nil, states: [:], relays: [], at: homeNow) == nil)
}

@Test func staleBalanceCardKeepsItsOldAmountAndStaleStatus() {
    let source = HomeCardSource.resolve(.provider(.deepseek),
        states: [.deepseek: homeState(.deepseek, balances: [CurrencyBalance(currency: "CNY", total: 8)])],
        relays: [], at: homeNow.addingTimeInterval(901))
    guard case .providerBalance(let presentation) = source else { Issue.record("旧读数仍是余额卡"); return }
    #expect(presentation.balances.first?.balance.total == 8)
    #expect(presentation.isStale)
    #expect(presentation.status == "旧读数")
}
