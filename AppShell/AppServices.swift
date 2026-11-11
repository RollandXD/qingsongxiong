import AIUsageData
import BearPlatform
import Foundation

/// App 级依赖的真身。
///
/// 历史服务必须**全 App 只有一个**：它内部缓存整份归档，
/// 两个实例各拿一份缓存会互相覆盖对方的观测点。
enum AppServices {
    static func localContainer() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("QingSongXiong", isDirectory: true)
    }

    static let history: any UsageHistoryRecording = {
        guard let container = try? localContainer(),
              let service = try? UsageHistoryService(container: container) else {
            return UnavailableUsageHistory()
        }
        return service
    }()
}
