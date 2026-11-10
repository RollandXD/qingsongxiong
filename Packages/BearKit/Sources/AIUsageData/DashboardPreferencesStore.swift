import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation

public struct FileDashboardPreferencesStore: DashboardPreferencesStoring {
    private let container: URL
    public init(container: URL) { self.container = container }

    private func store() throws -> AtomicRecordStore<DashboardPreferences> {
        try AtomicRecordStore(container: container, namespace: "ai-usage-dashboard")
    }

    public func load() throws -> DashboardPreferences? { try store().read() }

    public func save(_ preferences: DashboardPreferences) throws {
        // 旧进程可能还在写更早的时间戳；被拒时不算失败，下一次读取会拿到更新的那份。
        _ = try store().write(preferences)
    }
}
