import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DeepSeekAdapter: Sendable {
    private let client: any HTTPClient
    private let clock: any BearClock
    public init(client: any HTTPClient, clock: any BearClock = SystemBearClock()) {
        self.client = client
        self.clock = clock
    }

    public func fetch(apiKey: String) async throws -> UsageSnapshot {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 }) else {
            throw UsageFailure.invalidCredential
        }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: HTTPResponse
        do { response = try await client.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw UsageFailure.network }
        try HTTPUsagePolicy.validate(response, now: clock.now())
        return try UsageResponseParser.deepseek(response.data, fetchedAt: clock.now())
    }
}

public enum HTTPUsagePolicy {
    public static func validate(_ response: HTTPResponse, now: Date) throws {
        switch response.statusCode {
        case 200...299: return
        case 401: throw UsageFailure.reconnectRequired
        case 429:
            var retryAt: Date?
            if let raw = response.headers["retry-after"] {
                if let seconds = Double(raw), seconds.isFinite, seconds >= 0 {
                    retryAt = now.addingTimeInterval(seconds)
                } else {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: 0)
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    retryAt = formatter.date(from: raw)
                }
            }
            throw UsageFailure.rateLimited(retryAt: retryAt)
        default: throw UsageFailure.serviceHTTP(status: response.statusCode)
        }
    }
}
