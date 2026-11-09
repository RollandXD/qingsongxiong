import AIUsageDomain
import Foundation

/// 共享容器/签名能力不可用时不发起网络请求。
public struct VerificationGatedRelayRepository: RelayRepository {
    public init() {}
    public func states() async throws -> [RelayState] { [] }
    public func save(id: UUID?, name: String, endpoint: RelayEndpoint, key: String) async throws { throw UsageFailure.deviceVerificationRequired }
    public func refresh(_ id: UUID) async throws -> RelaySnapshot { throw UsageFailure.deviceVerificationRequired }
    public func delete(_ id: UUID) async throws { throw UsageFailure.deviceVerificationRequired }
    public func clear() async throws {}
}
