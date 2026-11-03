import BearFoundation
import BearPlatform
import Foundation
import Testing

private func temporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test func independentReadersSeeSharedSnapshotAndOlderWritesLose() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let app = try AtomicRecordStore<SigningProbeRecord>(container: root, namespace: "probe")
    let widget = try AtomicRecordStore<SigningProbeRecord>(container: root, namespace: "probe")
    let new = SigningProbeRecord(revision: 2, updatedAt: Date(timeIntervalSince1970: 200))
    let old = SigningProbeRecord(revision: 1, updatedAt: Date(timeIntervalSince1970: 100))
    #expect(try app.write(new))
    #expect(try !widget.write(old))
    #expect(try widget.read() == new)
    try app.remove()
    #expect(try widget.read() == nil)
}

@Test func namespacesAreIsolated() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let notes = try AtomicRecordStore<SigningProbeRecord>(container: root, namespace: "notes")
    let counter = try AtomicRecordStore<SigningProbeRecord>(container: root, namespace: "counter")
    try notes.write(SigningProbeRecord(revision: 9, updatedAt: Date()))
    #expect(try counter.read() == nil)
    #expect(throws: AtomicRecordStore<SigningProbeRecord>.StoreError.invalidNamespace) {
        try AtomicRecordStore<SigningProbeRecord>(container: root, namespace: "../other")
    }
}

@Test func concurrentWritersKeepNewestRecord() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicRecordStore<SigningProbeRecord>(container: root, namespace: "concurrent")
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<32 {
            group.addTask {
                try store.write(SigningProbeRecord(revision: index, updatedAt: Date(timeIntervalSince1970: Double(index))))
            }
        }
        try await group.waitForAll()
    }
    #expect(try store.read()?.revision == 31)
}

@Test func futureSchemaIsNotSilentlyOverwritten() throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicRecordStore<SigningProbeRecord>(container: root, namespace: "future")
    let path = root.appendingPathComponent("future/snapshot.json")
    try Data(#"{"schemaVersion":99,"record":{"revision":1,"updatedAt":0}}"#.utf8).write(to: path)
    #expect(throws: AtomicRecordStore<SigningProbeRecord>.StoreError.unsupportedVersion) { try store.read() }
}
