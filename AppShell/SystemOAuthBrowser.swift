import AIUsageAuth
import AIUsageDomain
import AuthenticationServices
import Foundation
import UIKit

/// 通用系统浏览器桥接，不包含任何厂商端点、凭据存储或额度规则。
@MainActor
final class SystemOAuthBrowser: NSObject, OAuthBrowserAuthorizing, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(url: URL, receiver: LoopbackCallbackReceiver) async throws -> URL {
        guard session == nil else { throw UsageFailure.unavailable }
        let current = ASWebAuthenticationSession(url: url, callbackURLScheme: "qingsongxiong") { _, error in
            if error != nil { Task { await receiver.cancel() } }
        }
        current.presentationContextProvider = self
        current.prefersEphemeralWebBrowserSession = false
        session = current
        defer { current.cancel(); session = nil }
        guard current.start() else { throw UsageFailure.unavailable }
        return try await withTaskCancellationHandler {
            try await receiver.waitForCallback()
        } onCancel: { [weak self] in
            Task { await receiver.cancel() }
            Task { @MainActor [weak self] in self?.session?.cancel() }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
