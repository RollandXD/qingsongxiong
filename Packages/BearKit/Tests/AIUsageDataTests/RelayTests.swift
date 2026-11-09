import AIUsageData
import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation
import Testing
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct RelayClock: BearClock { func now() -> Date { RelayContractFixtures.date } }
private actor RelayClient: HTTPClient {
    var response: HTTPResponse
    private(set) var requests: [URLRequest] = []
    init(_ code: Int = 200, data: Data = RelayContractFixtures.balance, headers: [String: String] = [:]) {
        response = HTTPResponse(data: data, statusCode: code, headers: headers)
    }
    func send(_ request: URLRequest) async throws -> HTTPResponse { requests.append(request); return response }
    func set(_ code: Int, data: Data = RelayContractFixtures.balance) { response = HTTPResponse(data: data, statusCode: code) }
}

@Test func relayContractPreservesDecimalsZeroNegativeAndFalse() throws {
    let first = try RelayBalanceAdapter.parse(RelayContractFixtures.balance, endpoint: .balance, at: RelayContractFixtures.date)
    #expect(first.balances.first?.total == Decimal(string: "12.34567890123456789"))
    #expect(first.balances.first?.currency == "USD")
    #expect(first.isAvailable == true)
    let zero = try RelayBalanceAdapter.parse(RelayContractFixtures.zero, endpoint: .balance, at: RelayContractFixtures.date)
    #expect(zero.balances.first?.total == 0)
    #expect(zero.isAvailable == false)
    let negative = try RelayBalanceAdapter.parse(RelayContractFixtures.negative, endpoint: .balance, at: RelayContractFixtures.date)
    #expect(negative.balances.first?.total == Decimal(string: "-0.25"))
    #expect(negative.isAvailable == nil)
}
@Test func relayUsageRespectsNullishPriorityAndUnits() throws {
    let values = [RelayContractFixtures.quota, RelayContractFixtures.usagePriority,
        Data(#"{"remaining":null,"quota":{"remaining":0,"unit":"credits"},"balance":"99","is_active":false,"isValid":true}"#.utf8)]
    let expected: [(Decimal, String)] = [(Decimal(string: "2500.125")!, "credits"), (Decimal(string: "7.5")!, "points"), (0, "credits")]
    for (data, value) in zip(values, expected) {
        let result = try RelayBalanceAdapter.parse(data, endpoint: .usage, at: RelayContractFixtures.date)
        #expect(result.balances.first?.total == value.0)
        #expect(result.balances.first?.currency == value.1)
    }
    #expect(try RelayBalanceAdapter.parse(values[2], endpoint: .usage, at: RelayContractFixtures.date).isAvailable == false)
}
@Test func relayRejectsMalformedAmountInsteadOfInventingZero() {
    for data in RelayContractFixtures.invalid {
        #expect(throws: UsageFailure.invalidResponse) { try RelayBalanceAdapter.parse(data, endpoint: .balance, at: RelayContractFixtures.date) }
    }
}
@Test func relayOnlyBuildsReviewedRequestsAndNeverAcceptsRedirectResponses() async throws {
    let client = RelayClient()
    _ = try await RelayBalanceAdapter(client: client).fetch(endpoint: .balance, key: "fixture-key")
    let request = try #require(await client.requests.first)
    #expect(request.url?.absoluteString == "https://api.apikey.fan/user/balance")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
    for status in [301, 302, 307, 308] {
        let redirect = RelayClient(status, headers: ["Location": "https://other.invalid/collect"])
        await #expect(throws: UsageFailure.invalidResponse) { try await RelayBalanceAdapter(client: redirect).fetch(endpoint: .usage, key: "fixture-key") }
        #expect(await redirect.requests.count == 1)
    }
}
@Test func relayAuthAndRateLimitAreExplicit() async {
    for status in [401, 403] {
        await #expect(throws: UsageFailure.reconnectRequired) { try await RelayBalanceAdapter(client: RelayClient(status)).fetch(endpoint: .balance, key: "fixture-key") }
    }
    let client = RelayClient(429, headers: ["Retry-After": "120"])
    await #expect(throws: UsageFailure.rateLimited(retryAt: RelayContractFixtures.date.addingTimeInterval(120))) {
        try await RelayBalanceAdapter(client: client, clock: RelayClock()).fetch(endpoint: .balance, key: "fixture-key")
    }
    let invalid = RelayClient()
    await #expect(throws: UsageFailure.invalidCredential) { try await RelayBalanceAdapter(client: invalid).fetch(endpoint: .balance, key: "fixture\r\nkey") }
    #expect(await invalid.requests.isEmpty)
}

private final class RelayRecords: RelayRecordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: RelayRecord?
    var reject = false
    func load() throws -> RelayRecord? { lock.withLock { value } }
    func save(_ record: RelayRecord) throws { try lock.withLock { if reject { throw UsageFailure.unavailable }; value = record } }
}
private final class RelayKeys: RelayCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]
    func load(_ account: RelayAccount) throws -> String? { lock.withLock { values[account.sessionID] } }
    func save(_ key: String, for account: RelayAccount) throws { lock.withLock { values[account.sessionID] = key } }
    func remove(_ account: RelayAccount) throws { lock.withLock { values[account.sessionID] = nil } }
    var count: Int { lock.withLock { values.count } }
}
@Test func relayFailedReplacementKeepsOriginalAccountAndKeyAndDeleteClearsThem() async throws {
    let records = RelayRecords(); let keys = RelayKeys(); let client = RelayClient()
    let repository = LiveRelayRepository(store: records, credentials: keys, adapter: RelayBalanceAdapter(client: client))
    try await repository.save(id: nil, name: "合成账户", endpoint: .balance, key: "old-fixture")
    let first = try #require(try await repository.states().first)
    await client.set(401)
    await #expect(throws: UsageFailure.reconnectRequired) { try await repository.save(id: first.id, name: "替换", endpoint: .usage, key: "next-fixture") }
    #expect(try await repository.states().first == first)
    #expect(try keys.load(first.account) == "old-fixture")
    await client.set(200)
    try await repository.save(id: first.id, name: "改名", endpoint: .balance, key: "")
    let changed = try #require(try await repository.states().first)
    #expect(changed.account.displayName == "改名")
    #expect(changed.account.sessionID != first.account.sessionID)
    #expect(try keys.load(first.account) == nil)
    #expect(try keys.load(changed.account) == "old-fixture")
    let bytes = try JSONEncoder().encode(try #require(try records.load()))
    #expect(!String(decoding: bytes, as: UTF8.self).contains("fixture"))
    try await repository.delete(first.id)
    #expect(try await repository.states().isEmpty)
    #expect(keys.count == 0)
}
@Test func relayPersistenceFailureRollsBackNewCredentialSlot() async throws {
    let records = RelayRecords(); let keys = RelayKeys()
    let repository = LiveRelayRepository(store: records, credentials: keys, adapter: RelayBalanceAdapter(client: RelayClient()))
    try await repository.save(id: nil, name: "原账户", endpoint: .balance, key: "old-fixture")
    let old = try #require(try await repository.states().first)
    records.reject = true
    await #expect(throws: UsageFailure.unavailable) { try await repository.save(id: old.id, name: "未提交", endpoint: .balance, key: "new-fixture") }
    #expect(try await repository.states().first == old)
    #expect(keys.count == 1)
    #expect(try keys.load(old.account) == "old-fixture")
}
@Test func relayWidgetReadsWithoutWritingAndHidesDeletedAccounts() async throws {
    let records = RelayRecords(); let keys = RelayKeys(); let client = RelayClient()
    let repository = LiveRelayRepository(store: records, credentials: keys, adapter: RelayBalanceAdapter(client: client))
    try await repository.save(id: nil, name: "合成账户", endpoint: .balance, key: "fixture-key")
    let initial = try #require(try records.load())
    let state = try #require(initial.states.first)
    let reader = WidgetRelayReader(store: records, credentials: keys, adapter: RelayBalanceAdapter(client: client))
    let reading = await reader.state(state.id, refresh: true, force: true)
    #expect(reading?.snapshot != nil)
    #expect(try records.load() == initial)
    try await repository.delete(state.id)
    #expect(await reader.state(state.id, refresh: false) == nil)
}
