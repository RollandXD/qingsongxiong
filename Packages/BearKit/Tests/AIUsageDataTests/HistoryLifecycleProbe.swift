import AIUsageData
import AIUsageDomain
import Foundation

/// 让仓储在历史 await 处可控停住；用 continuation 复现交错，不靠 sleep 猜时序。
actor HistoryLifecycleProbe: UsageHistoryRecording {
    enum Pause { case none, segment, record, forget }
    let pause: Pause
    let failRecord: Bool
    let failSegment: Bool
    var failForget: Bool
    private var paused = false
    private var resume: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var records: [AccountRef] = []
    private(set) var forgotten: [AccountRef] = []
    init(pause: Pause = .none, failRecord: Bool = false,
         failSegment: Bool = false, failForget: Bool = false) {
        self.pause = pause; self.failRecord = failRecord
        self.failSegment = failSegment; self.failForget = failForget
    }
    func allowRemoval() { failForget = false }
    func archive() async throws -> UsageHistoryArchive { .empty(at: Date(timeIntervalSince1970: 0)) }
    func beginSegment(for ref: AccountRef) async throws {
        if failSegment { throw UsageHistoryFailure.unavailable }
        await suspend(at: .segment)
    }
    func record(snapshot: UsageSnapshot, for ref: AccountRef) async throws {
        try await record(balances: snapshot.balances, at: snapshot.fetchedAt, for: ref)
    }
    func record(balances: [CurrencyBalance], at date: Date, for ref: AccountRef) async throws {
        if failRecord { throw UsageHistoryFailure.unavailable }
        await suspend(at: .record)
        records.append(ref)
    }
    func forget(_ ref: AccountRef) async throws {
        if failForget { throw UsageHistoryFailure.unavailable }
        await suspend(at: .forget)
        forgotten.append(ref)
    }
    private func suspend(at point: Pause) async {
        guard pause == point, !paused else { return }
        paused = true
        await withCheckedContinuation { continuation in
            resume = continuation
            started?.resume(); started = nil
        }
    }
    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { resume?.resume(); resume = nil }
}
