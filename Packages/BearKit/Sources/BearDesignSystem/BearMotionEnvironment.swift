import SwiftUI

private struct BearReducedMotionOverride: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// 系统值只读；测试只能加强减弱动效，不能关闭用户已启用的辅助功能。
    var bearReduceMotion: Bool {
        get { accessibilityReduceMotion || self[BearReducedMotionOverride.self] }
        set { self[BearReducedMotionOverride.self] = newValue }
    }
}
