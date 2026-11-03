import BearFoundation
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// 一个命名空间内的版本化快照；文件锁跨 App / Widget 进程生效。
public struct AtomicRecordStore<Record: TimestampedRecord>: Sendable {
    public enum StoreError: Error, Equatable { case invalidNamespace, lockUnavailable, unsupportedVersion }
    private struct Envelope: Codable {
        let schemaVersion: Int
        let record: Record
    }
    private let directory: URL
    private var recordURL: URL { directory.appendingPathComponent("snapshot.json") }

    public init(container: URL, namespace: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !namespace.isEmpty, namespace.unicodeScalars.allSatisfy(allowed.contains) else {
            throw StoreError.invalidNamespace
        }
        directory = container.appendingPathComponent(namespace, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    public func read() throws -> Record? { try withLock { try readUnlocked() } }

    @discardableResult
    public func write(_ record: Record) throws -> Bool {
        try withLock {
            if let previous = try readUnlocked(), previous.updatedAt > record.updatedAt { return false }
            let data = try JSONEncoder().encode(Envelope(schemaVersion: 1, record: record))
            try data.write(to: recordURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
            return true
        }
    }

    public func remove() throws {
        try withLock {
            if FileManager.default.fileExists(atPath: recordURL.path) {
                try FileManager.default.removeItem(at: recordURL)
            }
        }
    }

    private func readUnlocked() throws -> Record? {
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: recordURL))
        guard envelope.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
        return envelope.record
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        let descriptor = open(directory.appendingPathComponent("snapshot.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw StoreError.lockUnavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw StoreError.lockUnavailable }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }
}
