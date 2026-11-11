import AIUsageDomain
@testable import AIUsageFeature
import Foundation
import Testing

private let referenceNow = Date(timeIntervalSince1970: 1_800_000_000)

@MainActor
private func referenceJar(periods: Bool = true) throws -> HomeCardSource {
    let windows = try [("rate_limit.primary_window", "5 小时", 18_000),
                       ("rate_limit.secondary_window", "本周", 604_800)].map { id, label, seconds in
        try QuotaWindow(id: id, label: label, usedPercent: 20,
                        resetsAt: referenceNow.addingTimeInterval(Double(seconds) / 2),
                        periodSeconds: periods ? seconds : nil)
    }
    let state = ProviderState(provider: .codex, sessionID: UUID(), connection: .connected,
        snapshot: UsageSnapshot(provider: .codex, windows: windows, balances: [],
                                isAvailable: true, fetchedAt: referenceNow),
        failure: nil, updatedAt: referenceNow)
    return HomeCardSource.resolve(.provider(.codex), states: [.codex: state], relays: [], at: referenceNow)!
}

@MainActor @Test
func bothCurrentAndWeeklyJarCellsHaveTheirOwnPaceReference() throws {
    guard case .provider(let jar) = try referenceJar() else { Issue.record("应为额度蜜罐"); return }
    let cells = jar.cells(now: referenceNow, offset: 0)
    #expect(cells.count == 2)
    #expect(cells[0].reference == 0.5)
    #expect(cells[1].reference == 0.5)
    #expect(cells.map(\.value) == ["80", "80"])
}

@MainActor @Test
func jarReferencesDisappearWhenThePeriodIsUnknownOrPreviewingTheFuture() throws {
    guard case .provider(let unknown) = try referenceJar(periods: false),
          case .provider(let known) = try referenceJar() else { Issue.record("应为额度蜜罐"); return }
    #expect(unknown.cells(now: referenceNow, offset: 0).allSatisfy { $0.reference == nil })
    #expect(known.cells(now: referenceNow, offset: 3_600).allSatisfy { $0.reference == nil })
    #expect(known.cells(now: referenceNow.addingTimeInterval(901), offset: 0).allSatisfy { $0.reference == nil })
}
