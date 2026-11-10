import Foundation

/// 首页主卡选择的存储契约。
///
/// 放在 Domain 而不是 Data：`AIUsageFeature` 需要注入它，但架构边界不允许
/// 界面层依赖 `AIUsageData`。实现可以下沉到 Data（落盘）或留在测试里（内存）。
public protocol DashboardPreferencesStoring: Sendable {
    func load() throws -> DashboardPreferences?
    func save(_ preferences: DashboardPreferences) throws
}

/// 预览与测试用的内存实现，不落盘。
public final class MemoryDashboardPreferencesStore: DashboardPreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: DashboardPreferences?
    public init(_ initial: DashboardPreferences? = nil) { value = initial }

    public func load() throws -> DashboardPreferences? { lock.withLock { value } }
    public func save(_ preferences: DashboardPreferences) throws { lock.withLock { value = preferences } }
}
