import AIUsageDomain
import Foundation

struct OAuthConfiguration: Sendable {
    enum TokenEncoding: Sendable { case json, form }
    let provider: ProviderID
    let clientID: String
    let authorizeURL: URL
    let tokenURL: URL
    let scopes: String
    let callbackPath: String
    let callbackHost: String
    let fixedPort: UInt16?
    let tokenEncoding: TokenEncoding

    static func configuration(for provider: ProviderID) throws -> OAuthConfiguration {
        switch provider {
        case .codex:
            return OAuthConfiguration(provider: provider, clientID: "app_EMoamEEZ73f0CkXaXp7hrann",
                authorizeURL: URL(string: "https://auth.openai.com/oauth/authorize")!,
                tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
                scopes: "openid profile email offline_access api.connectors.read api.connectors.invoke",
                callbackPath: "/auth/callback", callbackHost: "127.0.0.1", fixedPort: 1455, tokenEncoding: .form)
        case .claude:
            return OAuthConfiguration(provider: provider, clientID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
                authorizeURL: URL(string: "https://claude.com/cai/oauth/authorize")!,
                tokenURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
                scopes: "org:create_api_key user:profile", callbackPath: "/callback", callbackHost: "localhost",
                fixedPort: nil, tokenEncoding: .json)
        case .deepseek: throw UsageFailure.invalidCredential
        }
    }
}

enum AIUsageHTTPIdentity {
    static let userAgent = "QingSongXiong/0.1 (iOS; +https://github.com/RollandXD/qingsongxiong)"
    static let claudeBeta = "oauth-2025-04-20"
}
