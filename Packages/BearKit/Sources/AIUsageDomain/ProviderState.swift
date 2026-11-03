import BearFoundation
import Foundation

public enum AccountConnection: String, Codable, Equatable, Sendable { case disconnected, connected, reconnectRequired, unknown }

public struct ProviderState: TimestampedRecord, Equatable {
    public let provider: ProviderID
    public let sessionID: UUID?
    public let connection: AccountConnection
    public let snapshot: UsageSnapshot?
    public let failure: UsageFailure?
    public let updatedAt: Date

    public init(provider: ProviderID, sessionID: UUID?, connection: AccountConnection,
                snapshot: UsageSnapshot?, failure: UsageFailure?, updatedAt: Date) {
        self.provider = provider
        self.sessionID = sessionID
        self.connection = connection
        self.snapshot = snapshot
        self.failure = failure
        self.updatedAt = updatedAt
    }

    public static func disconnected(_ provider: ProviderID, at date: Date) -> ProviderState {
        ProviderState(provider: provider, sessionID: nil, connection: .disconnected,
                      snapshot: nil, failure: nil, updatedAt: date)
    }

    public func isStale(at date: Date) -> Bool {
        guard let snapshot else { return true }
        return date.timeIntervalSince(snapshot.fetchedAt) >= 15 * 60 || failure != nil
    }
}
