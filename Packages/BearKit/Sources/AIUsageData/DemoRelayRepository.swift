#if DEBUG
import AIUsageDomain
import Foundation

/// 合成合同数据：数据层、展示层测试和 UI 演示共用；不包含真实账号或密钥。
public enum RelayContractFixtures {
    public static let date = Date(timeIntervalSince1970: 1_800_000_000)
    public static let balance = Data(#"{"balance":"12.34567890123456789","is_active":true}"#.utf8)
    public static let zero = Data(#"{"balance":0,"is_active":false}"#.utf8)
    public static let negative = Data(#"{"balance":"-0.25"}"#.utf8)
    public static let quota = Data(#"{"quota":{"remaining":"2500.125","unit":"credits"},"isValid":true}"#.utf8)
    public static let usagePriority = Data(#"{"remaining":"7.5","balance":"99","quota":{"remaining":"88","unit":"tokens"},"unit":"points"}"#.utf8)
    public static let invalid = [#"{}"#, #"{"balance":null}"#, #"{"balance":true}"#,
        #"{"balance":"12oops"}"#, #"{"balance":"NaN"}"#, #"{"balance":"1e1000"}"#,
        #"{"balance":[]}"#, #"{"balance":{}}"#, #"{"balance":" 12"}"#].map { Data($0.utf8) }
}
public actor DemoRelayRepository: RelayRepository {
    private var values: [RelayState]
    public init() {
        let account = RelayAccount(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!, displayName: "我的中转")
        let snapshot = try! RelayBalanceAdapter.parse(RelayContractFixtures.balance, endpoint: .balance, at: Date())
        values = [RelayState(account: account, snapshot: snapshot, updatedAt: snapshot.fetchedAt)]
    }
    public func states() async throws -> [RelayState] { values }
    public func save(id: UUID?, name: String, endpoint: RelayEndpoint, key: String) async throws {
        try await Task.sleep(for: .milliseconds(300))
        try Task.checkCancellation()
        guard key != "invalid-demo" else { throw UsageFailure.reconnectRequired }
        let account = RelayAccount(id: id ?? UUID(), displayName: name, endpoint: endpoint)
        let snapshot = try RelayBalanceAdapter.parse(endpoint == .balance ? RelayContractFixtures.balance : RelayContractFixtures.quota, endpoint: endpoint, at: Date())
        values.removeAll { $0.id == id }
        values.append(RelayState(account: account, snapshot: snapshot, updatedAt: Date()))
    }
    public func refresh(_ id: UUID) async throws -> RelaySnapshot {
        try await Task.sleep(for: .milliseconds(300))
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw UsageFailure.disconnected }
        let account = values[index].account
        let snapshot = try RelayBalanceAdapter.parse(account.endpoint == .balance ? RelayContractFixtures.balance : RelayContractFixtures.quota, endpoint: account.endpoint, at: Date())
        values[index] = RelayState(account: account, snapshot: snapshot, updatedAt: Date())
        return snapshot
    }
    public func delete(_ id: UUID) async throws { values.removeAll { $0.id == id } }
    public func clear() async throws { values = [] }
}
#endif
