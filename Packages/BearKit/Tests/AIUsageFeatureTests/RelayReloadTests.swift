import AIUsageDomain
import AIUsageFeature
import Foundation
import Testing

private actor ReloadRelayRepository: RelayRepository {
    private var values: [RelayState]
    private var nextFailure: UsageFailure?
    private var nextBalance: Decimal = 10
    private var nextAvailable = true
    init() {
        let date = Date(timeIntervalSinceNow: -600)
        values = [RelayState(account: RelayAccount(displayName: "合成中转"),
            snapshot: RelaySnapshot(balances: [CurrencyBalance(currency: "USD", total: 10)], isAvailable: true, fetchedAt: date), updatedAt: date)]
    }
    func states() async throws -> [RelayState] { values }
    func configure(balance: Decimal = 10, available: Bool = true, failure: UsageFailure? = nil) {
        nextBalance = balance; nextAvailable = available; nextFailure = failure
    }
    func refresh(_ id: UUID) async throws -> RelaySnapshot {
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw UsageFailure.disconnected }
        let old = values[index]
        if let nextFailure {
            values[index] = RelayState(account: old.account, snapshot: old.snapshot, failure: nextFailure, updatedAt: Date())
            throw nextFailure
        }
        let snapshot = RelaySnapshot(balances: [CurrencyBalance(currency: "USD", total: nextBalance)],
            isAvailable: nextAvailable, fetchedAt: Date())
        values[index] = RelayState(account: old.account, snapshot: snapshot, updatedAt: Date())
        return snapshot
    }
    func save(id: UUID?, name: String, endpoint: RelayEndpoint, key: String) async throws {
        guard let index = values.firstIndex(where: { $0.id == id }) else { throw UsageFailure.disconnected }
        let old = values[index]
        values[index] = RelayState(account: RelayAccount(id: old.id, displayName: name, endpoint: endpoint),
            snapshot: old.snapshot, updatedAt: Date())
    }
    func delete(_ id: UUID) async throws { values.removeAll { $0.id == id } }
    func clear() async throws { values = [] }
}

@Test @MainActor func relayTimestampsDoNotReloadButBalanceAvailabilityAndFailureChangesDo() async throws {
    let repository = ReloadRelayRepository()
    var reloads = 0
    let model = RelayModel(repository: repository, onDataChange: { reloads += 1 })
    await model.load()
    let id = try #require(model.states.first?.id)
    #expect(await model.refresh(id))
    #expect(reloads == 0)
    #expect(model.feedback[id] == "已核实，余额未变化")
    await repository.configure(balance: -1)
    #expect(await model.refresh(id))
    #expect(reloads == 1)
    await repository.configure(balance: -1, available: false)
    #expect(await model.refresh(id))
    #expect(reloads == 2)
    await repository.configure(failure: .network)
    #expect(!(await model.refresh(id, report: false)))
    #expect(reloads == 3)
    #expect(model.states.first?.snapshot?.balances.first?.total == -1)
    #expect(!(await model.refresh(id, report: false)))
    #expect(reloads == 3)
    await repository.configure(balance: -1, available: false)
    #expect(await model.refresh(id))
    #expect(reloads == 4)
}

@Test @MainActor func relayCredentialGenerationAndRemovalReloadEvenWhenReadingsMatch() async throws {
    let repository = ReloadRelayRepository()
    var reloads = 0
    let model = RelayModel(repository: repository, onDataChange: { reloads += 1 })
    await model.load()
    let old = try #require(model.states.first)
    #expect(await model.save(id: old.id, name: old.account.displayName, endpoint: old.account.endpoint, key: ""))
    #expect(model.states.first?.account.sessionID != old.account.sessionID)
    #expect(reloads == 1)
    #expect(await model.delete(old.id))
    #expect(model.states.isEmpty)
    #expect(reloads == 2)
}
