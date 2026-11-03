import Foundation

public protocol TimestampedRecord: Codable, Sendable {
    var updatedAt: Date { get }
}

public protocol SecureValueStore: Sendable {
    func read(key: String) throws -> Data?
    func write(_ data: Data, key: String) throws
    func remove(key: String) throws
}

public struct SigningProbeRecord: TimestampedRecord, Equatable {
    public let revision: Int
    public let updatedAt: Date

    public init(revision: Int, updatedAt: Date) {
        self.revision = revision
        self.updatedAt = updatedAt
    }
}
