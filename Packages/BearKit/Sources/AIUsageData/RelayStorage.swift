import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation

public struct RelayRecord: TimestampedRecord, Equatable {
    public let states: [RelayState]
    public let updatedAt: Date
    public let retiredAccounts: [RelayAccount]?
    public init(states: [RelayState], retiredAccounts: [RelayAccount] = [], updatedAt: Date) {
        self.states = states; self.retiredAccounts = retiredAccounts; self.updatedAt = updatedAt
    }
}
public protocol RelayRecordReading: Sendable { func load() throws -> RelayRecord? }
public protocol RelayRecordStoring: RelayRecordReading { func save(_ record: RelayRecord) throws }
public struct FileRelayStore: RelayRecordStoring {
    private let store: AtomicRecordStore<RelayRecord>
    public init(container: URL) throws { store = try AtomicRecordStore(container: container, namespace: "ai-usage-relays") }
    public func load() throws -> RelayRecord? { try store.read() }
    public func save(_ record: RelayRecord) throws {
        guard try store.write(record) else { throw UsageFailure.unavailable }
    }
}
public protocol RelayCredentialReading: Sendable { func load(_ account: RelayAccount) throws -> String? }
public protocol RelayCredentialStoring: RelayCredentialReading {
    func save(_ key: String, for account: RelayAccount) throws
    func remove(_ account: RelayAccount) throws
}
/// 账户 UUID + 代次形成不可变的凭据槽；验证失败不修改旧槽。
public struct SecureRelayCredentials: RelayCredentialStoring {
    private let values: any SecureValueStore
    public init(values: any SecureValueStore) { self.values = values }
    private func slot(_ account: RelayAccount) -> String { "ai-usage.relay." + account.id.uuidString + "." + account.sessionID.uuidString }
    public func load(_ account: RelayAccount) throws -> String? {
        guard let data = try values.read(key: slot(account)) else { return nil }
        guard let key = String(data: data, encoding: .utf8) else { throw UsageFailure.invalidCredential }
        return key
    }
    public func save(_ key: String, for account: RelayAccount) throws { try values.write(Data(key.utf8), key: slot(account)) }
    public func remove(_ account: RelayAccount) throws { try values.remove(key: slot(account)) }
}
