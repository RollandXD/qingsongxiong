import AIUsageDomain
import AIUsagePresentation
import Foundation
import Testing

private let boundaryNow = Date(timeIntervalSince1970: 1_800_000_000)
private let boundaryRef = AccountRef.provider(.claude)
private let boundaryMetric = UsageHistoryMetric.quota(windowID: "five_hour")
private func boundaryEntry(_ remaining: Double, reset: Date?) -> HistoryEntry {
    HistoryEntry(metric: boundaryMetric, value: .percent(remaining), resetsAt: reset)
}
private func boundaryPresentation(_ observations: [UsageObservation]) -> UsageTimelinePresentation {
    UsageTimelinePresentation(archive: UsageHistoryArchive(sources: [
        UsageHistorySource(source: boundaryRef, observations: observations)
    ], updatedAt: boundaryNow), ref: boundaryRef, metric: boundaryMetric,
    range: .day, now: boundaryNow, metricLabel: "短期窗口")
}

@Test func serverResetBoundaryBreaksDenseObservationsWithoutGuessingFromValueChanges() {
    let old = boundaryNow.addingTimeInterval(-100)
    let next = boundaryNow.addingTimeInterval(18_000)
    let rows = [
        UsageObservation(at: boundaryNow.addingTimeInterval(-600), segment: 0,
                         entries: [boundaryEntry(10, reset: old)]),
        UsageObservation(at: boundaryNow.addingTimeInterval(-300), segment: 0,
                         entries: [boundaryEntry(8, reset: old)]),
        UsageObservation(at: boundaryNow, segment: 0,
                         entries: [boundaryEntry(99, reset: next)])
    ]
    let shown = boundaryPresentation(rows)
    #expect(shown.bands.map { $0.points.count } == [2, 1])
    #expect(shown.pointCount == 3)
}

@Test func missingWindowBetweenTwoSamplesCannotBeBridged() {
    let reset = boundaryNow.addingTimeInterval(3_600)
    let rows = [
        UsageObservation(at: boundaryNow.addingTimeInterval(-600), segment: 0,
                         entries: [boundaryEntry(70, reset: reset)]),
        UsageObservation(at: boundaryNow.addingTimeInterval(-300), segment: 0,
                         entries: [HistoryEntry(metric: .quota(windowID: "seven_day"), value: .percent(50))]),
        UsageObservation(at: boundaryNow, segment: 0, entries: [boundaryEntry(60, reset: reset)])
    ]
    #expect(boundaryPresentation(rows).bands.map { $0.points.count } == [1, 1])
}

@Test func repeatedEmptySessionsStillAdvanceAndDoNotExposeOldMetrics() {
    var archive = UsageHistoryArchive(sources: [UsageHistorySource(source: boundaryRef,
        observations: [UsageObservation(at: boundaryNow, segment: 0,
                                        entries: [boundaryEntry(70, reset: nil)])])], updatedAt: boundaryNow)
    archive = UsageHistoryReducer.beginningSegment(for: boundaryRef, in: archive, now: boundaryNow)
    archive = UsageHistoryReducer.beginningSegment(for: boundaryRef, in: archive, now: boundaryNow)
    #expect(archive.source(boundaryRef)?.segment == 2)
    #expect(archive.metrics(for: boundaryRef).isEmpty)
    #expect(archive.series(for: boundaryRef, metric: boundaryMetric).isEmpty)
    #expect(archive.observations(for: boundaryRef).count == 1, "存储可按保留期留存，但 UI 不可读取旧 session")
}

@Test func legacyHistoryEntryWithoutResetMetadataStillDecodes() throws {
    let old = boundaryEntry(40, reset: nil)
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    json.removeValue(forKey: "resetsAt")
    let decoded = try JSONDecoder().decode(HistoryEntry.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(decoded.value == .percent(40))
    #expect(decoded.resetsAt == nil)
}
