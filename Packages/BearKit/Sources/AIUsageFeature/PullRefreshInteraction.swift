import Foundation

/// 下拉手势状态独立于 SwiftUI，避免每帧几何变化触发业务请求。
public struct PullRefreshInteraction: Equatable, Sendable {
    public private(set) var distance = 0.0
    public private(set) var refreshing = false
    public var armed: Bool { distance >= 80 }
    public var progress: Double { min(1, max(0, distance / 80)) }
    public init() {}
    public mutating func begin() { if !refreshing { distance = 0 } }
    public mutating func observe(distance: Double) {
        guard !refreshing, distance.isFinite else { return }
        self.distance = min(160, max(0, distance))
    }
    public mutating func release(enabled: Bool) -> Bool {
        guard enabled, armed, !refreshing else { distance = 0; return false }
        refreshing = true
        distance = 0
        return true
    }
    public mutating func finish() { refreshing = false; distance = 0 }
}
