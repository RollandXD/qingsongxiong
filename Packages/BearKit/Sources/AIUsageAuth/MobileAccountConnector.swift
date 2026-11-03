import AIUsageData
import AIUsageDomain
import Foundation

public protocol OAuthBrowserAuthorizing: Sendable {
    @MainActor func authorize(url: URL, receiver: LoopbackCallbackReceiver) async throws -> URL
}

/// 交互授权只链接到主 App；退出账户时同步取消尚未完成的登录。
public actor MobileAccountConnector: AIUsageAccountConnecting {
    private let repository: LiveAIUsageRepository
    private let tokenClient: OAuthTokenClient
    private let browser: any OAuthBrowserAuthorizing
    private struct Attempt { let id: UUID; let task: Task<Void, any Error> }
    private var attempts: [ProviderID: Attempt] = [:]

    public init(repository: LiveAIUsageRepository, tokenClient: OAuthTokenClient,
                browser: any OAuthBrowserAuthorizing) {
        self.repository = repository
        self.tokenClient = tokenClient
        self.browser = browser
    }

    public nonisolated func supports(_ provider: ProviderID) -> Bool { true }

    public func connect(_ provider: ProviderID, apiKey: String?) async throws {
        try Task.checkCancellation()
        guard attempts.isEmpty else { throw UsageFailure.unavailable }
        let id = UUID()
        let task = Task { try await self.perform(provider, apiKey: apiKey) }
        attempts[provider] = Attempt(id: id, task: task)
        defer { if attempts[provider]?.id == id { attempts[provider] = nil } }
        try await withTaskCancellationHandler { try await task.value }
            onCancel: { Task { await self.cancelAttempt(provider, id: id) } }
    }

    private func cancelAttempt(_ provider: ProviderID, id: UUID) async {
        guard attempts[provider]?.id == id else { return }
        await cancel(provider)
    }

    public func cancel(_ provider: ProviderID) async {
        attempts.removeValue(forKey: provider)?.task.cancel()
        await repository.cancel(provider)
    }

    private func perform(_ provider: ProviderID, apiKey: String?) async throws {
        if provider == .deepseek { try await repository.connect(provider, apiKey: apiKey); return }
        let config = try OAuthConfiguration.configuration(for: provider)
        let proof = try AuthorizationProof.generate()
        let receiver = LoopbackCallbackReceiver(path: config.callbackPath, host: config.callbackHost,
                                                state: proof.state, fixedPort: config.fixedPort)
        do {
            let port = try await receiver.start()
            let pending = try await tokenClient.begin(provider: provider, port: port, proof: proof)
            let callback = try await browser.authorize(url: pending.url, receiver: receiver)
            await receiver.stop()
            try Task.checkCancellation()
            let credential = try await tokenClient.exchange(callback: callback, pending: pending)
            try Task.checkCancellation()
            try await repository.replaceCredential(credential, for: provider)
        } catch {
            await receiver.stop()
            throw error
        }
    }
}
