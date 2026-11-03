import AIUsageData
import AIUsageDomain
import Testing

@Test func deviceGateDoesNotReturnPretendUsage() async throws {
    let repository = VerificationGatedRepository()
    for provider in ProviderID.allCases {
        #expect(try await repository.cachedSnapshot(for: provider) == nil)
        await #expect(throws: UsageFailure.deviceVerificationRequired) { try await repository.refresh(provider) }
    }
}
