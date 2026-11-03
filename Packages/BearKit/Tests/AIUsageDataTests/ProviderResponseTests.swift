import AIUsageData
import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation
import Testing

private let referenceTime = Date(timeIntervalSince1970: 1_800_000_000)
private func bytes(_ text: String) -> Data { Data(text.utf8) }

@Test func deepSeekKeepsDecimalPrecisionAndEveryCurrency() throws {
    let data = bytes(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"0.10000000000001","granted_balance":"0.00000000000001","topped_up_balance":"0.1"},{"currency":"USD","total_balance":"10.25"}]}"#)
    let value = try UsageResponseParser.deepseek(data, fetchedAt: referenceTime)
    #expect(value.balances.count == 2)
    #expect(value.balances[0].total == Decimal(string: "0.10000000000001"))
    #expect(value.balances[1].currency == "USD")
    #expect(value.balances[1].granted == nil)
    #expect(value.isAvailable == true)
    #expect(value.fetchedAt == referenceTime)
}

@Test func insufficientDeepSeekBalanceRemainsAnExplicitServiceResult() throws {
    let value = try UsageResponseParser.deepseek(bytes(#"{"is_available":false,"balance_infos":[{"currency":"CNY","total_balance":"-0.01"}]}"#), fetchedAt: referenceTime)
    #expect(value.isAvailable == false)
    #expect(value.balances.first?.total == Decimal(string: "-0.01"))
    let missing = try UsageResponseParser.deepseek(bytes(#"{"balance_infos":[]}"#), fetchedAt: referenceTime)
    #expect(missing.isAvailable == nil)
    #expect(missing.balances.isEmpty)
}

@Test func malformedAndMissingBalancesCannotBecomeZero() {
    for raw in [#"{"is_available":true}"#,
                #"{"balance_infos":[{"currency":"CNY","total_balance":"9oops"}]}"#,
                #"{"balance_infos":[{"currency":"CNY","total_balance":"1e3"}]}"#,
                #"{"balance_infos":[{"currency":"CNY","total_balance":"1\n"}]}"#] {
        #expect(throws: UsageFailure.invalidResponse) {
            try UsageResponseParser.deepseek(bytes(raw), fetchedAt: referenceTime)
        }
    }
}

@Test func codexUsesReturnedWindowDurationsAndResetTime() throws {
    let raw = #"{"rate_limit":{"primary_window":{"used_percent":100,"limit_window_seconds":18000,"reset_at":1799999990},"secondary_window":{"used_percent":12.5,"limit_window_seconds":604800,"reset_after_seconds":60}},"code_review_rate_limit":{"primary_window":{"used_percent":3,"limit_window_seconds":86400}}}"#
    let value = try UsageResponseParser.codex(bytes(raw), fetchedAt: referenceTime)
    #expect(value.windows.map(\.label) == ["5 小时", "7 天", "代码审查 · 1 天"])
    #expect(value.windows[0].usedPercent == 100)
    #expect(value.windows[0].resetsAt! < referenceTime)
    #expect(value.windows[1].usedPercent == 12.5)
    #expect(value.windows[1].resetsAt == referenceTime.addingTimeInterval(60))
}

@Test func codexRejectsMissingAndBooleanQuotaFields() {
    for raw in [#"{}"#, #"{"rate_limit":{"primary_window":{"used_percent":true}}}"#,
                #"{"rate_limit":{"primary_window":{"used_percent":-2}}}"#] {
        #expect(throws: UsageFailure.invalidResponse) {
            try UsageResponseParser.codex(bytes(raw), fetchedAt: referenceTime)
        }
    }
}

@Test func claudePreservesEveryModelWindowAndFractionalPercentage() throws {
    let raw = #"{"five_hour":{"utilization":24.9,"resets_at":"2027-01-15T08:00:00.000Z"},"seven_day":{"utilization":15,"resets_at":"2027-01-16T08:00:00Z"},"seven_day_opus":{"percent":7},"seven_day_sonnet":{"utilization":8}}"#
    let value = try UsageResponseParser.claude(bytes(raw), fetchedAt: referenceTime)
    #expect(value.windows.count == 4)
    #expect(value.windows.first?.usedPercent == 24.9)
    #expect(value.windows[0].resetsAt != nil)
    #expect(value.windows[1].resetsAt != nil)
    #expect(value.windows[2].resetsAt == nil)
}

@Test func absentClaudeModelWindowsAreNotReportedAsUnused() throws {
    let value = try UsageResponseParser.claude(bytes(#"{"five_hour":null,"seven_day":{"utilization":80},"seven_day_sonnet":null}"#), fetchedAt: referenceTime)
    #expect(value.windows.count == 1)
    #expect(value.windows[0].id == "seven_day")
    #expect(throws: UsageFailure.invalidResponse) {
        try UsageResponseParser.claude(bytes(#"{"five_hour":null}"#), fetchedAt: referenceTime)
    }
}

private struct FixedClock: BearClock {
    func now() -> Date { referenceTime }
}

private actor ResponseClient: HTTPClient {
    let response: HTTPResponse
    private var count = 0
    init(_ response: HTTPResponse) { self.response = response }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        count += 1
        #expect(request.url?.absoluteString == "https://api.deepseek.com/user/balance")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-key")
        return response
    }
    func calls() -> Int { count }
}

@Test func deepSeekRateLimitHonorsRetryAfterWithoutReturningInventedUsage() async {
    let client = ResponseClient(HTTPResponse(data: bytes("{}"), statusCode: 429, headers: ["Retry-After": "120"]))
    let adapter = DeepSeekAdapter(client: client, clock: FixedClock())
    await #expect(throws: UsageFailure.rateLimited(retryAt: referenceTime.addingTimeInterval(120))) {
        try await adapter.fetch(apiKey: "unit-key")
    }
}

@Test func deepSeekAuthorizationFailureRequiresReconnection() async {
    let client = ResponseClient(HTTPResponse(data: bytes("{}"), statusCode: 401))
    await #expect(throws: UsageFailure.reconnectRequired) {
        try await DeepSeekAdapter(client: client).fetch(apiKey: "unit-key")
    }
}

@Test func invalidHeaderValueDoesNotMakeAnHTTPCall() async {
    let client = ResponseClient(HTTPResponse(data: bytes("{}"), statusCode: 200))
    await #expect(throws: UsageFailure.invalidCredential) {
        try await DeepSeekAdapter(client: client).fetch(apiKey: "unit\r\nkey")
    }
    #expect(await client.calls() == 0)
}
