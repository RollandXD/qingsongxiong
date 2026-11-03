import AIUsageDomain
import AIUsageFeature
import Foundation
import Testing

@Test @MainActor func onlyOneProviderCanBeExpandedAndRepeatedActionsDoNotQueue() {
    let interaction = DashboardInteraction()
    interaction.toggle(.codex)
    interaction.toggle(.claude)
    #expect(interaction.expandedProvider == .claude)
    interaction.toggle(.claude)
    #expect(interaction.expandedProvider == nil)
    interaction.toggle(.deepseek)
    #expect(interaction.expandedProvider == .deepseek)
}

@Test @MainActor func changingAccountClearsOldFocusAndExpansion() throws {
    let interaction = DashboardInteraction()
    let window = try QuotaWindow(id: "five_hour", label: "5 小时", usedPercent: 20, resetsAt: nil)
    func makeState() -> ProviderState {
        ProviderState(provider: .claude, sessionID: UUID(), connection: .connected,
            snapshot: UsageSnapshot(provider: .claude, windows: [window], balances: [], isAvailable: nil, fetchedAt: Date()),
            failure: nil, updatedAt: Date())
    }
    interaction.reconcile([.claude: makeState()])
    interaction.toggle(.claude)
    interaction.focus(window.id, for: .claude)
    interaction.reconcile([.claude: makeState()])
    #expect(interaction.expandedProvider == nil)
    #expect(interaction.focusedWindows[.claude] == nil)
}
