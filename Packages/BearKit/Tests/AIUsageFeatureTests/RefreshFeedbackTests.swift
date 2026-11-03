import AIUsageDomain
import AIUsageFeature
import Foundation
import Testing

private actor FeedbackRepository: AIUsageRepository {
    private var value: ProviderState
    private let changes: Bool
    private let fails: Bool
    init(changes: Bool = false, fails: Bool = false) throws {
        self.changes = changes; self.fails = fails
        value = Self.sample(session: UUID(), used: 10, date: Date(timeIntervalSince1970: 1_800_000_000))
    }
    private static func sample(session: UUID?, used: Double, date: Date) -> ProviderState {
        let window = try! QuotaWindow(id: "five_hour", label: "5 小时", usedPercent: used, resetsAt: nil)
        return ProviderState(provider: .claude, sessionID: session, connection: .connected,
            snapshot: UsageSnapshot(provider: .claude, windows: [window], balances: [], isAvailable: nil, fetchedAt: date),
            failure: nil, updatedAt: date)
    }
    func state(for provider: ProviderID) async throws -> ProviderState {
        provider == .claude ? value : .disconnected(provider, at: value.updatedAt)
    }
    func cachedSnapshot(for provider: ProviderID) async throws -> UsageSnapshot? { value.snapshot }
    func refresh(_ provider: ProviderID) async throws -> UsageSnapshot {
        if fails { throw UsageFailure.network }
        value = Self.sample(session: value.sessionID, used: changes ? 20 : 10, date: value.updatedAt.addingTimeInterval(1))
        return value.snapshot!
    }
    func disconnect(_ provider: ProviderID) async throws { value = .disconnected(provider, at: value.updatedAt) }
}

@Test(arguments: [false, true]) @MainActor
func everyManualRefreshDistinguishesVerificationFromARealValueChange(changes: Bool) async throws {
    let model = AIUsageModel(repository: try FeedbackRepository(changes: changes), connector: nil)
    await model.loadCached()
    await model.refresh(.claude)
    #expect(model.verifiedRefresh.contains(.claude))
    #expect(model.refreshFeedback[.claude] == (changes ? "已更新读数" : "已核实，读数未变化"))
    #expect(model.states[.claude]?.snapshot?.windows.first?.remainingPercent == (changes ? 80 : 90))
}

@Test @MainActor func aFailedRefreshCannotProduceSuccessFeedbackFromAnOldHealthyState() async throws {
    let model = AIUsageModel(repository: try FeedbackRepository(fails: true), connector: nil)
    await model.loadCached()
    let previous = model.states[.claude]?.snapshot
    await model.refresh(.claude, reportFailure: false)
    #expect(model.states[.claude]?.snapshot == previous)
    #expect(!model.verifiedRefresh.contains(.claude))
    #expect(model.refreshFeedback[.claude] == "读取未完成，已保留原状态")
}
