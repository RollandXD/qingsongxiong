import AIUsageDomain

/// 免费签名与共享能力通过前，真实厂商接入保持关闭。
public actor VerificationGatedRepository: AIUsageRepository {
    public init() {}
    public func state(for provider: ProviderID) async throws -> ProviderState {
        .disconnected(provider, at: .distantPast)
    }
    public func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot? { nil }
    public func refresh(_ provider: ProviderID) async throws -> UsageSnapshot {
        throw UsageFailure.deviceVerificationRequired
    }
    public func disconnect(_ provider: ProviderID) async throws {}
}
