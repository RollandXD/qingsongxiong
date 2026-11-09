import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// 处理器由 App 的 .backgroundTask(.appRefresh(identifier)) 在 Scene 创建时注册。
/// SwiftUI 负责系统 expiration → Task cancellation；仓储向下取消网络请求。
@MainActor
enum UsageBackgroundRefresh {
    static let identifier = "io.github.rollandxd.qingsongxiong.refresh"
    static private(set) var lastScheduleSucceeded: Bool?
    static func schedule() {
        #if os(iOS) && !targetEnvironment(simulator)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do { try BGTaskScheduler.shared.submit(request); lastScheduleSucceeded = true }
        catch { lastScheduleSucceeded = false }
        #endif
    }
}
