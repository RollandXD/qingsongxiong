import AIUsageData
import AIUsageDomain
import BearFoundation
import BearPlatform
import CoreFoundation
import Foundation

struct PendingAuthorization: Sendable {
    let url: URL
    let config: OAuthConfiguration
    let proof: AuthorizationProof
    let redirectURI: String
}

/// 仅负责协议交换与续期，凭据持久化由主 App 仓储串行完成。
public actor OAuthTokenClient: UsageCredentialRenewing {
    private let client: any HTTPClient
    private let clock: any BearClock
    public init(client: any HTTPClient, clock: any BearClock = SystemBearClock()) {
        self.client = client
        self.clock = clock
    }

    func begin(provider: ProviderID, port: UInt16, proof: AuthorizationProof) throws -> PendingAuthorization {
        let config = try OAuthConfiguration.configuration(for: provider)
        if let fixed = config.fixedPort, fixed != port { throw UsageFailure.invalidResponse }
        let redirect = "http://\(config.callbackHost):\(port)\(config.callbackPath)"
        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "client_id", value: config.clientID),
                     URLQueryItem(name: "response_type", value: "code"),
                     URLQueryItem(name: "redirect_uri", value: redirect),
                     URLQueryItem(name: "scope", value: config.scopes),
                     URLQueryItem(name: "state", value: proof.state),
                     URLQueryItem(name: "code_challenge", value: proof.challenge),
                     URLQueryItem(name: "code_challenge_method", value: "S256")]
        if provider == .claude { items.append(URLQueryItem(name: "code", value: "true")) }
        if provider == .codex {
            items.append(URLQueryItem(name: "originator", value: "qingsongxiong"))
        }
        components.queryItems = items
        guard let url = components.url else { throw UsageFailure.invalidResponse }
        return PendingAuthorization(url: url, config: config, proof: proof, redirectURI: redirect)
    }

    func exchange(callback: URL, pending: PendingAuthorization) async throws -> ProviderCredential {
        guard let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let expected = URLComponents(string: pending.redirectURI),
              components.scheme == expected.scheme, components.host == expected.host, components.port == expected.port,
              components.path == pending.config.callbackPath else { throw UsageFailure.invalidResponse }
        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }.compactMap(\.value)
        let codes = items.filter { $0.name == "code" }.compactMap(\.value)
        guard states == [pending.proof.state] else { throw UsageFailure.invalidResponse }
        guard !items.contains(where: { $0.name == "error" }) else { throw CancellationError() }
        guard codes.count == 1 else { throw UsageFailure.invalidResponse }
        let parts = codes[0].split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let code = parts.first, !code.isEmpty else { throw UsageFailure.invalidResponse }
        if parts.count == 2, parts[1] != pending.proof.state { throw UsageFailure.invalidResponse }
        let body = ["grant_type": "authorization_code", "code": code,
                    "redirect_uri": pending.redirectURI, "client_id": pending.config.clientID,
                    "code_verifier": pending.proof.verifier, "state": pending.proof.state]
        return try await token(body, config: pending.config, existing: nil, exchange: true)
    }

    public func renew(_ credential: ProviderCredential, for provider: ProviderID) async throws -> ProviderCredential {
        guard let refreshToken = credential.refreshToken else { throw UsageFailure.reconnectRequired }
        let config = try OAuthConfiguration.configuration(for: provider)
        var body = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": config.clientID]
        if let scope = credential.scope, !scope.isEmpty { body["scope"] = scope }
        return try await token(body, config: config, existing: credential, exchange: false)
    }

    private func token(_ body: [String: String], config: OAuthConfiguration,
                       existing: ProviderCredential?, exchange: Bool) async throws -> ProviderCredential {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AIUsageHTTPIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        if exchange && config.provider == .claude {
            request.setValue(AIUsageHTTPIdentity.claudeBeta, forHTTPHeaderField: "anthropic-beta")
        }
        switch config.tokenEncoding {
        case .json:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        case .form:
            var form = URLComponents()
            form.queryItems = body.filter { $0.key != "state" }.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        }
        let response: HTTPResponse
        do { response = try await client.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw UsageFailure.network }
        let object = (try? JSONSerialization.jsonObject(with: response.data)) as? [String: Any]
        if response.statusCode == 400, let error = object?["error"] as? String,
           ["invalid_grant", "invalid_token"].contains(error) { throw UsageFailure.reconnectRequired }
        if response.statusCode == 400, let error = object?["error"] as? String,
           ["invalid_scope", "invalid_client", "invalid_request"].contains(error) { throw UsageFailure.authorizationRejected }
        try HTTPUsagePolicy.validate(response, now: clock.now())
        guard let object, let accessToken = object["access_token"] as? String,
              !accessToken.isEmpty, accessToken.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 }),
              let expiresIn = object["expires_in"] as? NSNumber, expiresIn.doubleValue.isFinite,
              CFGetTypeID(expiresIn) != CFBooleanGetTypeID(),
              expiresIn.doubleValue > 0 else { throw UsageFailure.invalidResponse }
        let claims = (object["id_token"] as? String).flatMap(Self.claims)
        let accountID = ((claims?["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String)
            ?? claims?["chatgpt_account_id"] as? String ?? existing?.accountID
        return ProviderCredential(sessionID: existing?.sessionID ?? UUID(), accessToken: accessToken,
            refreshToken: object["refresh_token"] as? String ?? existing?.refreshToken,
            expiresAt: clock.now().addingTimeInterval(expiresIn.doubleValue), accountID: accountID,
            scope: object["scope"] as? String ?? existing?.scope)
    }

    /// 仅提取额度请求所需账户头，不以未验证 JWT 声明作身份或权限判断。
    private static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
