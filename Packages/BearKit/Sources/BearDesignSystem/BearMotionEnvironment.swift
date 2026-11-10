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

/// 打开 App 设置的动作：App 外壳注入，各功能首页在导航栏放置「设置」按钮调用。
public struct BearOpenSettingsAction: Sendable {
    private let action: @MainActor @Sendable () -> Void
    public init(_ action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
    @MainActor public func callAsFunction() { action() }
}

public extension EnvironmentValues {
    @Entry var bearOpenSettings: BearOpenSettingsAction? = nil
}
