import AIUsageDomain
import Foundation
import Testing

private let prefsNow = Date(timeIntervalSince1970: 1_800_000_000)

@Test func defaultPreferencesFollowPreviousHomeOrder() {
    let prefs = DashboardPreferences.initial(at: prefsNow)
    #expect(prefs.cards.count == DashboardPreferences.slotCount)
    #expect(prefs.ref(atSlot: 0) == .provider(.codex))
    #expect(prefs.ref(atSlot: 1) == .provider(.claude))
    #expect(prefs.selectedRefs == [.provider(.codex), .provider(.claude)])
}

@Test func slotsNeverRepeatAndAlwaysHaveFixedLength() {
    let relay = UUID()
    let prefs = DashboardPreferences(cards: [.relay(relay), .relay(relay)], updatedAt: prefsNow)
    #expect(prefs.cards.count == 2)
    #expect(prefs.ref(atSlot: 0) == .relay(relay))
    // 重复项被清空，而不是把同一账户放两次。
    #expect(prefs.ref(atSlot: 1) == nil)

    let short = DashboardPreferences(cards: [.provider(.deepseek)], updatedAt: prefsNow)
    #expect(short.cards.count == 2)
    #expect(short.ref(atSlot: 1) == nil)

    let long = DashboardPreferences(cards: [.provider(.codex), .provider(.claude), .provider(.deepseek)],
                                    updatedAt: prefsNow)
    #expect(long.cards.count == 2)
    #expect(!long.cards.contains(.provider(.deepseek)))
}

@Test func settingAnAlreadySelectedAccountSwapsInsteadOfDuplicating() {
    let relay = UUID()
    var prefs = DashboardPreferences.initial(at: prefsNow)
    prefs = prefs.setting(.relay(relay), atSlot: 0, at: prefsNow)
    #expect(prefs.ref(atSlot: 0) == .relay(relay))
    #expect(prefs.ref(atSlot: 1) == .provider(.claude))

    // 把 slot 1 换成已在 slot 0 的值：两格互换，不能重复。
    prefs = prefs.setting(.relay(relay), atSlot: 1, at: prefsNow)
    #expect(prefs.ref(atSlot: 0) == .provider(.claude))
    #expect(prefs.ref(atSlot: 1) == .relay(relay))

    // 余额卡也能占两格：这里再放一个中转账户。
    prefs = prefs.setting(.provider(.deepseek), atSlot: 0, at: prefsNow)
    #expect(prefs.selectedRefs == [.provider(.deepseek), .relay(relay)])
}

@Test func emptySlotSurvivesAndCanBeFilled() {
    var prefs = DashboardPreferences(cards: [nil, .provider(.claude)], updatedAt: prefsNow)
    #expect(prefs.ref(atSlot: 0) == nil)
    prefs = prefs.setting(.provider(.codex), atSlot: 0, at: prefsNow)
    #expect(prefs.selectedRefs == [.provider(.codex), .provider(.claude)])
}

@Test func deletingRelayClearsOnlyItsSlot() {
    let relay = UUID()
    let prefs = DashboardPreferences(cards: [.relay(relay), .provider(.claude)], updatedAt: prefsNow)
    let after = prefs.removingRelay(relay, at: prefsNow)
    #expect(after.ref(atSlot: 0) == nil)
    #expect(after.ref(atSlot: 1) == .provider(.claude))
    // 其他中转删除不影响选择。
    #expect(prefs.removingRelay(UUID(), at: prefsNow) == prefs)
}

@Test func swappingSlotsKeepsBothAccounts() {
    let relay = UUID()
    let prefs = DashboardPreferences(cards: [.provider(.codex), .relay(relay)], updatedAt: prefsNow)
    let swapped = prefs.swapping(0, 1, at: prefsNow)
    #expect(swapped.ref(atSlot: 0) == .relay(relay))
    #expect(swapped.ref(atSlot: 1) == .provider(.codex))
    // 越界与同位置都原样返回。
    #expect(prefs.swapping(0, 5, at: prefsNow) == prefs)
    #expect(prefs.swapping(1, 1, at: prefsNow) == prefs)
}

@Test func preferencesRoundTripAndTolerateDamagedFile() throws {
    let relay = UUID()
    let prefs = DashboardPreferences(cards: [nil, .relay(relay)], updatedAt: prefsNow)
    let data = try JSONEncoder().encode(prefs)
    let decoded = try JSONDecoder().decode(DashboardPreferences.self, from: data)
    #expect(decoded == prefs)

    // 手改出重复项的坏文件：解码后仍然合法。
    let damaged = Data(#"{"revision":1,"updatedAt":0,"cards":[{"kind":"provider","provider":"codex"},{"kind":"provider","provider":"codex"}]}"#.utf8)
    let repaired = try JSONDecoder().decode(DashboardPreferences.self, from: damaged)
    #expect(repaired.cards.count == 2)
    #expect(repaired.ref(atSlot: 0) == .provider(.codex))
    #expect(repaired.ref(atSlot: 1) == nil)

    // 未知主卡类型不能把整份偏好搞崩。
    let unknown = Data(#"{"updatedAt":0,"cards":[{"kind":"watch","provider":"codex"}]}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(DashboardPreferences.self, from: unknown) }
}

@Test func accountRefEncodesAsReadableKeys() throws {
    let relay = UUID()
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let providerJSON = String(decoding: try encoder.encode(AccountRef.provider(.claude)), as: UTF8.self)
    let relayJSON = String(decoding: try encoder.encode(AccountRef.relay(relay)), as: UTF8.self)
    // 写进文件的键要能直接看懂，而不是合成的 `_0`。
    #expect(providerJSON == #"{"kind":"provider","provider":"claude"}"#)
    #expect(relayJSON == "{\"id\":\"" + relay.uuidString + "\",\"kind\":\"relay\"}")
}

@Test func providerAndRelayReferencesStayDistinct() {
    let id = UUID()
    #expect(AccountRef.provider(.claude) != .relay(id))
    #expect(AccountRef.provider(.claude).id == "provider:claude")
    #expect(AccountRef.relay(id).id == "relay:" + id.uuidString)
    #expect(AccountRef.provider(.claude).isRelay == false)
    #expect(AccountRef.relay(id).relayID == id)
    #expect(AccountRef.provider(.claude).relayID == nil)
    #expect(AccountRef.relay(id).providerID == nil)
}
