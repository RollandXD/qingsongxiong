import AIUsageData
import BearPlatform

/// App 级依赖的真身。
///
/// 历史服务必须**全 App 只有一个**：它内部缓存整份归档，
/// 两个实例各拿一份缓存会互相覆盖对方的观测点。
enum AppServices {
    static let history: any UsageHistoryRecording = {
        guard let shared = try? SharedResources(),
              let container = try? shared.containerURL(),
              let service = try? UsageHistoryService(container: container) else {
            return DisabledUsageHistory()
        }
        return service
    }()
}
