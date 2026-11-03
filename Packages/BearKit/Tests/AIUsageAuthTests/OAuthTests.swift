@testable import AIUsageAuth
import AIUsageData
import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation
import Testing

private let oauthTime = Date(timeIntervalSince1970: 1_800_000_000)
private struct OAuthClock: BearClock { func now() -> Date { oauthTime } }
private let fixedProof = AuthorizationProof(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "unit-state")

private actor TokenResponseClient: HTTPClient {
    let response: HTTPResponse
    private var requests: [URLRequest] = []
    init(_ json: String, status: Int = 200) { response = HTTPResponse(data: Data(json.utf8), statusCode: status) }
    func send(_ request: URLRequest) async throws -> HTTPResponse { requests.append(request); return response }
    func last() -> URLRequest? { requests.last }
    func count() -> Int { requests.count }
}

@Test func pkceMatchesTheRFCVectorAndUsesIndependentSecureRandomValues() throws {
    #expect(fixedProof.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    let generated = try AuthorizationProof.generate()
    #expect(generated.verifier.count == 43)
    #expect(generated.state.count == 43)
    #expect(generated.verifier != generated.state)
}

@Test func codexUsesItsRegisteredIPv4LoopbackPathAndPKCE() async throws {
    let client = OAuthTokenClient(client: TokenResponseClient("{}"))
    let pending = try await client.begin(provider: .codex, port: 1455, proof: fixedProof)
    let query = URLComponents(url: pending.url, resolvingAgainstBaseURL: false)!.queryItems!
    #expect(pending.redirectURI == "http://127.0.0.1:1455/auth/callback")
    #expect(query.first { $0.name == "code_challenge" }?.value == fixedProof.challenge)
    #expect(query.first { $0.name == "state" }?.value == fixedProof.state)
}

@Test func callbackValidationRejectsChangedOriginStateDuplicatesAndEmptyCodesBeforeHTTP() async throws {
    let transport = TokenResponseClient("{}")
    let client = OAuthTokenClient(client: transport)
    let pending = try await client.begin(provider: .codex, port: 1455, proof: fixedProof)
    let bad = ["http://127.0.0.1:1455/auth/callback?code=x&state=wrong",
               "http://127.0.0.1:1455/auth/callback?code=x&state=unit-state&state=unit-state",
               "http://127.0.0.1:1455/auth/callback?code=%23&state=unit-state",
               "http://localhost:1455/auth/callback?code=x&state=unit-state"]
    for raw in bad {
        await #expect(throws: UsageFailure.invalidResponse) {
            try await client.exchange(callback: URL(string: raw)!, pending: pending)
        }
    }
    #expect(await transport.count() == 0)
}

@Test func authorizationDenialIsCancellationAndNeverExchangesACode() async throws {
    let transport = TokenResponseClient("{}")
    let client = OAuthTokenClient(client: transport)
    let pending = try await client.begin(provider: .codex, port: 1455, proof: fixedProof)
    await #expect(throws: CancellationError.self) {
        try await client.exchange(callback: URL(string: pending.redirectURI + "?error=access_denied&state=unit-state")!, pending: pending)
    }
    #expect(await transport.count() == 0)
}

@Test func codeExchangeFormEscapesPlusAndKeepsTheExactRedirect() async throws {
    let transport = TokenResponseClient(#"{"access_token":"unit-access","refresh_token":"unit-refresh","expires_in":3600}"#)
    let client = OAuthTokenClient(client: transport, clock: OAuthClock())
    let pending = try await client.begin(provider: .codex, port: 1455, proof: fixedProof)
    let result = try await client.exchange(callback: URL(string: pending.redirectURI + "?code=one%2Btwo&state=unit-state")!, pending: pending)
    let request = await transport.last()!
    let body = String(data: request.httpBody!, encoding: .utf8)!
    #expect(body.contains("code=one%2Btwo"))
    var components = URLComponents()
    components.percentEncodedQuery = body
    #expect(components.queryItems?.first { $0.name == "redirect_uri" }?.value == pending.redirectURI)
    #expect(!body.contains("client_secret"))
    #expect(result.refreshToken == "unit-refresh")
    #expect(result.expiresAt == oauthTime.addingTimeInterval(3600))
}

@Test func claudeRefreshReplaysOnlyGrantedScopesAndPreservesAccountGeneration() async throws {
    let transport = TokenResponseClient(#"{"access_token":"next-access","refresh_token":"next-refresh","expires_in":3600,"scope":"user:profile"}"#)
    let client = OAuthTokenClient(client: transport, clock: OAuthClock())
    let original = ProviderCredential(accessToken: "old-access", refreshToken: "old-refresh", scope: "user:profile")
    let result = try await client.renew(original, for: .claude)
    let request = await transport.last()!
    let body = try JSONDecoder().decode([String: String].self, from: request.httpBody!)
    #expect(body["scope"] == "user:profile")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
    #expect(result.sessionID == original.sessionID)
    #expect(result.refreshToken == "next-refresh")
}

@Test func rejectedRefreshGrantRequiresARealReconnect() async {
    let transport = TokenResponseClient(#"{"error":"invalid_grant"}"#, status: 400)
    let client = OAuthTokenClient(client: transport)
    await #expect(throws: UsageFailure.reconnectRequired) {
        try await client.renew(ProviderCredential(accessToken: "old", refreshToken: "revoked"), for: .claude)
    }
}

@Test func booleanTokenLifetimeIsNotAcceptedAsOneSecond() async {
    let client = OAuthTokenClient(client: TokenResponseClient(#"{"access_token":"unit-access","expires_in":true}"#))
    await #expect(throws: UsageFailure.invalidResponse) {
        try await client.renew(ProviderCredential(accessToken: "old", refreshToken: "unit-refresh"), for: .claude)
    }
}

@Test func loopbackRejectsUnrelatedRequestsThenAcceptsOnlyItsOwnState() async throws {
    let receiver = LoopbackCallbackReceiver(path: "/callback", host: "127.0.0.1", state: "unit-state", fixedPort: nil)
    let port = try await receiver.start()
    let waiting = Task { try await receiver.waitForCallback() }
    let client = URLSessionHTTPClient()
    let base = "http://127.0.0.1:\(port)"
    let wrong = try await client.send(URLRequest(url: URL(string: base + "/callback?code=x&state=wrong")!))
    #expect(wrong.statusCode == 400)
    let correct = try await client.send(URLRequest(url: URL(string: base + "/callback?code=unit-code&state=unit-state")!))
    #expect(correct.statusCode == 200)
    let callback = try await waiting.value
    #expect(URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "code" }?.value == "unit-code")
    await receiver.stop()
}

@Test func loopbackCancellationResumesItsWaiter() async throws {
    let receiver = LoopbackCallbackReceiver(path: "/callback", host: "127.0.0.1", state: "unit-state", fixedPort: nil)
    _ = try await receiver.start()
    let waiting = Task { try await receiver.waitForCallback() }
    await receiver.cancel()
    await #expect(throws: CancellationError.self) { try await waiting.value }
}

private struct EmptyAuthCredentials: UsageCredentialStore {
    func load(_ provider: ProviderID) throws -> ProviderCredential? { nil }
    func save(_ credential: ProviderCredential, for provider: ProviderID) throws {
        Issue.record("取消后的登录不得保存凭据")
    }
    func remove(_ provider: ProviderID) throws {}
}

private struct EmptyAuthStates: UsageStateStore {
    func load(_ provider: ProviderID) throws -> ProviderState? { nil }
    func save(_ state: ProviderState) throws { Issue.record("取消后的登录不得保存额度") }
    func remove(_ provider: ProviderID) throws {}
}

@MainActor private final class DelayedAuthBrowser: OAuthBrowserAuthorizing {
    private var completion: CheckedContinuation<URL, Never>?
    private var presented: CheckedContinuation<Bool, Never>?
    private var callback: URL?
    func authorize(url: URL, receiver: LoopbackCallbackReceiver) async throws -> URL {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let redirect = query.first { $0.name == "redirect_uri" }!.value!
        let state = query.first { $0.name == "state" }!.value!
        var components = URLComponents(string: redirect)!
        components.queryItems = [URLQueryItem(name: "code", value: "unit-code"), URLQueryItem(name: "state", value: state)]
        callback = components.url!
        // 故意不响应 Task 取消，以模拟迟到的系统回调。
        return await withCheckedContinuation {
            completion = $0
            presented?.resume(returning: true); presented = nil
        }
    }
    func waitUntilPresented() async -> Bool {
        if completion != nil { return true }
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            presented?.resume(returning: false); presented = nil
        }
        defer { deadline.cancel() }
        return await withCheckedContinuation { presented = $0 }
    }
    func complete() { completion?.resume(returning: callback!); completion = nil }
}

@Test @MainActor func cancelledLoginRejectsALateBrowserCallbackBeforeTokenExchange() async throws {
    let transport = TokenResponseClient(#"{"access_token":"unit-access","expires_in":3600}"#)
    let tokens = OAuthTokenClient(client: transport)
    let repository = LiveAIUsageRepository(credentials: EmptyAuthCredentials(), states: EmptyAuthStates(), fetchers: [:])
    let browser = DelayedAuthBrowser()
    let connector = MobileAccountConnector(repository: repository, tokenClient: tokens, browser: browser)
    let login = Task { try await connector.connect(.claude, apiKey: nil) }
    guard await browser.waitUntilPresented() else {
        login.cancel(); Issue.record("未能在测试期限内打开授权浏览器"); return
    }
    await connector.cancel(.claude)
    browser.complete()
    await #expect(throws: CancellationError.self) { try await login.value }
    #expect(await transport.count() == 0)
    #expect(try await repository.state(for: .claude).connection == .disconnected)
}
