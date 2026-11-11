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
    var savesUntilRejection: Int?
    func load() throws -> RelayRecord? { lock.withLock { value } }
    func save(_ record: RelayRecord) throws {
        try lock.withLock {
            if reject { throw UsageFailure.unavailable }
            if let remaining = savesUntilRejection {
                if remaining == 0 { savesUntilRejection = nil; throw UsageFailure.unavailable }
                savesUntilRejection = remaining - 1
            }
            value = record
        }
    }
}
private final class RelayKeys: RelayCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]
    var rejectRemoval = false
    func load(_ account: RelayAccount) throws -> String? { lock.withLock { values[account.sessionID] } }
    func save(_ key: String, for account: RelayAccount) throws { lock.withLock { values[account.sessionID] = key } }
    func remove(_ account: RelayAccount) throws {
        try lock.withLock {
            if rejectRemoval { throw UsageFailure.unavailable }
            values[account.sessionID] = nil
        }
    }
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
@Test func relayCommitAndRollbackFailureKeepsRecoverableCredentialJournal() async throws {
    let records = RelayRecords(); let keys = RelayKeys()
    let repository = LiveRelayRepository(store: records, credentials: keys, adapter: RelayBalanceAdapter(client: RelayClient()))
    try await repository.save(id: nil, name: "原账户", endpoint: .balance, key: "old-fixture")
    let old = try #require(try await repository.states().first)
    records.savesUntilRejection = 1 // 恢复目录成功，最终提交失败。
    keys.rejectRemoval = true // 连回滚也失败，不能遗失新凭据的目录。
    await #expect(throws: UsageFailure.unavailable) {
        try await repository.save(id: old.id, name: "未提交", endpoint: .balance, key: "new-fixture")
    }
    #expect(try await repository.states().first == old)
    #expect(keys.count == 2)
    #expect(try records.load()?.retiredAccounts?.count == 1)
    keys.rejectRemoval = false
    try await repository.clear()
    #expect(keys.count == 0)
    #expect(try await repository.states().isEmpty)
    #expect(try records.load()?.retiredAccounts?.isEmpty ?? true)
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

@Test func relayWidgetKeepsRateLimitEvenWhenSnapshotTimestampDoesNotChange() async throws {
    let records = RelayRecords(); let keys = RelayKeys(); let client = RelayClient()
    let adapter = RelayBalanceAdapter(client: client, clock: RelayClock())
    let repository = LiveRelayRepository(store: records, credentials: keys, adapter: adapter, clock: RelayClock())
    try await repository.save(id: nil, name: "限流合成账户", endpoint: .balance, key: "fixture-key")
    let saved = try #require(try records.load())
    let account = try #require(saved.states.first)
    let reader = WidgetRelayReader(store: records, credentials: keys, adapter: adapter, clock: RelayClock())
    await client.set(429)
    let first = try #require(await reader.state(account.id, refresh: true, force: true))
    #expect(first.snapshot == account.snapshot)
    #expect(first.failure == .rateLimited(retryAt: RelayContractFixtures.date.addingTimeInterval(300)))
    let count = await client.requests.count
    let second = await reader.state(account.id, refresh: true, force: true)
    #expect(second?.failure == first.failure)
    #expect(await client.requests.count == count)
    #expect(await reader.state(account.id, refresh: false)?.failure == first.failure)
    #expect(try records.load() == saved)
}

@Test func relayHistoryFailureDoesNotEraseASuccessfulBalanceRefresh() async throws {
    let history = HistoryLifecycleProbe(failRecord: true)
    let repository = LiveRelayRepository(store: RelayRecords(), credentials: RelayKeys(),
        adapter: RelayBalanceAdapter(client: RelayClient()), history: history)
    try await repository.save(id: nil, name: "合成账户", endpoint: .balance, key: "fixture-key")
    let id = try #require(try await repository.states().first?.id)
    _ = try await repository.refresh(id)
    #expect(try await repository.states().first?.failure == nil)
    #expect(try await repository.states().first?.snapshot != nil)
}

@Test func relayDeletionFailureKeepsARetryableDirectoryInsteadOfClaimingPrivacySuccess() async throws {
    let records = RelayRecords(); let keys = RelayKeys()
    let history = HistoryLifecycleProbe(failForget: true)
    let repository = LiveRelayRepository(store: records, credentials: keys,
        adapter: RelayBalanceAdapter(client: RelayClient()), history: history)
    try await repository.save(id: nil, name: "合成账户", endpoint: .balance, key: "fixture-key")
    let id = try #require(try await repository.states().first?.id)
    await #expect(throws: UsageHistoryFailure.self) { try await repository.delete(id) }
    #expect(try await repository.states().count == 1)
    #expect(keys.count == 0)
    await history.allowRemoval()
    try await repository.delete(id)
    #expect(try await repository.states().isEmpty)
    #expect(await history.forgotten == [.relay(id)])
}

@Test func relayClearBlocksNewSavesWhileWaitingForHistoryDeletion() async throws {
    let history = HistoryLifecycleProbe(pause: .forget)
    let repository = LiveRelayRepository(store: RelayRecords(), credentials: RelayKeys(),
        adapter: RelayBalanceAdapter(client: RelayClient()), history: history)
    try await repository.save(id: nil, name: "旧账户", endpoint: .balance, key: "fixture-key")
    let id = try #require(try await repository.states().first?.id)
    let clearing = Task { try await repository.clear() }
    await history.waitUntilPaused()
    await #expect(throws: CancellationError.self) {
        try await repository.save(id: nil, name: "不能插队", endpoint: .balance, key: "fixture-key")
    }
    await #expect(throws: CancellationError.self) { try await repository.refresh(id) }
    await history.release()
    try await clearing.value
    #expect(try await repository.states().isEmpty)
}

@Test func relayDeletionReReadsTheDirectoryAfterHistoryAwaitSoOtherAccountsSurvive() async throws {
    let history = HistoryLifecycleProbe(pause: .forget)
    let repository = LiveRelayRepository(store: RelayRecords(), credentials: RelayKeys(),
        adapter: RelayBalanceAdapter(client: RelayClient()), history: history)
    try await repository.save(id: nil, name: "待删除", endpoint: .balance, key: "fixture-key")
    let first = try #require(try await repository.states().first?.id)
    let deletion = Task { try await repository.delete(first) }
    await history.waitUntilPaused()
    try await repository.save(id: nil, name: "另一个", endpoint: .balance, key: "fixture-key")
    await history.release()
    try await deletion.value
    #expect(try await repository.states().map(\.account.displayName) == ["另一个"])
}

@Test func relayReplacementCannotAppendHistoryAfterDeletionDuringSegmentAwait() async throws {
    let history = HistoryLifecycleProbe(pause: .segment)
    let repository = LiveRelayRepository(store: RelayRecords(), credentials: RelayKeys(),
        adapter: RelayBalanceAdapter(client: RelayClient()), history: history)
    try await repository.save(id: nil, name: "旧账户", endpoint: .balance, key: "fixture-key")
    let id = try #require(try await repository.states().first?.id)
    let replacement = Task {
        try await repository.save(id: id, name: "新账户", endpoint: .balance, key: "fixture-next")
    }
    await history.waitUntilPaused()
    try await repository.delete(id)
    await history.release()
    await #expect(throws: CancellationError.self) { try await replacement.value }
    #expect(await history.records == [.relay(id)], "只有最初连接的记录，没有删除后的迟到记录")
    #expect(try await repository.states().isEmpty)
}
