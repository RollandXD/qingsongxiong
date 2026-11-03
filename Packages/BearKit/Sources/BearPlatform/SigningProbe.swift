import BearFoundation
import Foundation

public struct ProbeReport: Sendable {
    public let record: SigningProbeRecord?
    public let sharedContainerAvailable: Bool
    public let sharedKeychainReadable: Bool
    public let keychainStatus: Int32?
    public let storageFailed: Bool
}

public struct SigningProbe: Sendable {
    public static let service = "io.github.rollandxd.qingsongxiong.signing-probe"
    private let groupIdentifiers: [String]
    private let keychainSuffix: String
    private let simulator: Bool
    private let identifierPrefix: String?

    public init(groupIdentifiers: [String], keychainSuffix: String, simulator: Bool = false,
                identifierPrefix: String? = nil) {
        self.groupIdentifiers = groupIdentifiers
        self.keychainSuffix = keychainSuffix
        self.simulator = simulator
        self.identifierPrefix = identifierPrefix
    }

    public static func configured(bundle: Bundle = .main) -> SigningProbe {
        let primary = bundle.object(forInfoDictionaryKey: "BearAppGroupIdentifier") as? String ?? ""
        let rewritten = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        let suffix = bundle.object(forInfoDictionaryKey: "BearKeychainGroupSuffix") as? String ?? ""
        let capabilities = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? ProfileCapabilities.decode($0) }
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return SigningProbe(groupIdentifiers: (capabilities?.matchingGroups(original: primary) ?? []) + rewritten + [primary],
                            keychainSuffix: suffix, simulator: isSimulator,
                            identifierPrefix: capabilities?.identifierPrefixes.first)
    }

    private func store() throws -> AtomicRecordStore<SigningProbeRecord>? {
        #if os(iOS)
        for identifier in groupIdentifiers where !identifier.isEmpty {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                return try AtomicRecordStore(container: url, namespace: "signing-probe")
            }
        }
        #endif
        return nil
    }

    private func vault() throws -> KeychainVault {
        if simulator { return KeychainVault(service: Self.service, accessGroup: nil) }
        let prefix = try identifierPrefix ?? KeychainVault.defaultTeamPrefix(service: Self.service)
        return KeychainVault(service: Self.service, accessGroup: prefix + "." + keychainSuffix)
    }

    public func inspect() -> ProbeReport {
        var record: SigningProbeRecord?
        var container = false
        var storageFailed = false
        do {
            if let store = try store() {
                container = true
                record = try store.read()
            }
        } catch { storageFailed = true }
        var readable = false
        var status: Int32?
        do { readable = try vault().read(key: "shared-marker") == Data("bear-probe-v1".utf8) }
        catch let error as KeychainVault.KeychainError { status = error.status }
        catch { status = -1 }
        return ProbeReport(record: record, sharedContainerAvailable: container,
                           sharedKeychainReadable: readable, keychainStatus: status, storageFailed: storageFailed)
    }

    public func write() throws {
        guard let store = try store() else { throw ProbeError.containerUnavailable }
        let previous = try store.read()?.revision ?? 0
        try store.write(SigningProbeRecord(revision: previous + 1, updatedAt: Date()))
        try vault().write(Data("bear-probe-v1".utf8), key: "shared-marker")
    }

    public enum ProbeError: Error { case containerUnavailable }
}
