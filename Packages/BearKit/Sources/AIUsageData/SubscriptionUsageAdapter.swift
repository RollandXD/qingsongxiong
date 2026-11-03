import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation

public struct SubscriptionUsageAdapter: UsageFetching {
    private let provider: ProviderID
    private let client: any HTTPClient
    private let clock: any BearClock
    public init(provider: ProviderID, client: any HTTPClient, clock: any BearClock = SystemBearClock()) {
        self.provider = provider
        self.client = client
        self.clock = clock
    }

    public func fetch(credential: ProviderCredential) async throws -> UsageSnapshot {
        let url: URL
        switch provider {
        case .codex: url = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        case .claude: url = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        case .deepseek: throw UsageFailure.invalidResponse
        }
        guard Self.safeHeader(credential.accessToken) else { throw UsageFailure.invalidCredential }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + credential.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QingSongXiong/0.1 (iOS; +https://github.com/RollandXD/qingsongxiong)", forHTTPHeaderField: "User-Agent")
        if provider == .claude { request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta") }
        if provider == .codex, let account = credential.accountID {
            guard Self.safeHeader(account) else { throw UsageFailure.invalidCredential }
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let response: HTTPResponse
        do { response = try await client.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw UsageFailure.network }
        try HTTPUsagePolicy.validate(response, now: clock.now())
        switch provider {
        case .codex: return try UsageResponseParser.codex(response.data, fetchedAt: clock.now())
        case .claude: return try UsageResponseParser.claude(response.data, fetchedAt: clock.now())
        case .deepseek: throw UsageFailure.invalidResponse
        }
    }

    private static func safeHeader(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { $0.isASCII && $0.value > 32 && $0.value < 127 }
    }
}
