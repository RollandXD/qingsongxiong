import Foundation

public protocol BearClock: Sendable {
    func now() -> Date
}

public struct SystemBearClock: BearClock {
    public init() {}
    public func now() -> Date { Date() }
}
