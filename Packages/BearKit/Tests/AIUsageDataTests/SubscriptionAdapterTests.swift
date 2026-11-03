import AIUsageData
import AIUsageDomain
import BearPlatform
import Foundation
import Testing

private actor SubscriptionClient: HTTPClient {
    let response: HTTPResponse
    private var request: URLRequest?
    init(_ body: String, status: Int = 200) {
        response = HTTPResponse(data: Data(body.utf8), statusCode: status)
    }
    func send(_ request: URLRequest) async throws -> HTTPResponse { self.request = request; return response }
    func last() -> URLRequest? { request }
}

@Test func codexUsageSendsItsAccountHeaderAndPreservesServiceWindows() async throws {
    let client = SubscriptionClient(#"{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000}}}"#)
    let snapshot = try await SubscriptionUsageAdapter(provider: .codex, client: client)
        .fetch(credential: ProviderCredential(accessToken: "unit-access", accountID: "unit-account"))
    let request = await client.last()
    #expect(request?.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
    #expect(request?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "unit-account")
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer unit-access")
    #expect(snapshot.provider == .codex)
    #expect(snapshot.windows.first?.usedPercent == 12)
}

@Test func claudeUsesOAuthUsageHeadersWithoutAnAPIKeyOrChatRequest() async throws {
    let client = SubscriptionClient(#"{"five_hour":{"utilization":37}}"#)
    let snapshot = try await SubscriptionUsageAdapter(provider: .claude, client: client)
        .fetch(credential: ProviderCredential(accessToken: "unit-access"))
    let request = await client.last()
    #expect(request?.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(request?.httpMethod == "GET")
    #expect(request?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(request?.value(forHTTPHeaderField: "x-api-key") == nil)
    #expect(snapshot.provider == .claude)
}

@Test func forbiddenUsageResponsePreservesItsStatusInsteadOfRotatingCredentials() async {
    let client = SubscriptionClient("{}", status: 403)
    await #expect(throws: UsageFailure.serviceHTTP(status: 403)) {
        try await SubscriptionUsageAdapter(provider: .claude, client: client)
            .fetch(credential: ProviderCredential(accessToken: "unit-access"))
    }
}
