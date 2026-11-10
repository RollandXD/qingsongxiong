import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation

/// 首页主卡选择的存储。与额度缓存同容器、独立命名空间，互不拖累。
public protocol DashboardPreferencesStoring: Sendable {
    func load() throws -> DashboardPreferences?
    func save(_ preferences: DashboardPreferences) throws
}

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

/// 预览与旧测试用的内存实现，不落盘。
public final class MemoryDashboardPreferencesStore: DashboardPreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: DashboardPreferences?
    public init(_ initial: DashboardPreferences? = nil) { value = initial }

    public func load() throws -> DashboardPreferences? { lock.withLock { value } }
    public func save(_ preferences: DashboardPreferences) throws { lock.withLock { value = preferences } }
}
