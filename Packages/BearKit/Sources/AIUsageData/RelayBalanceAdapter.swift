import AIUsageDomain
import BearFoundation
import BearPlatform
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct RelayBalanceAdapter: Sendable {
    private let client: any HTTPClient
    private let clock: any BearClock
    /// 生产环境必须装配 URLSessionHTTPClient(followRedirects: false)。
    public init(client: any HTTPClient, clock: any BearClock = SystemBearClock()) { self.client = client; self.clock = clock }
    public func fetch(endpoint: RelayEndpoint, key: String) async throws -> RelaySnapshot {
        let key = try Self.validatedKey(key)
        var request = URLRequest(url: URL(string: "https://api.apikey.fan" + endpoint.path)!)
        request.httpMethod = "GET"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QingSongXiong/0.3 relay-balance", forHTTPHeaderField: "User-Agent")
        let response: HTTPResponse
        do { response = try await client.send(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw UsageFailure.network }
        if response.statusCode == 403 { throw UsageFailure.reconnectRequired }
        if (300...399).contains(response.statusCode) { throw UsageFailure.invalidResponse }
        try HTTPUsagePolicy.validate(response, now: clock.now())
        let snapshot = try Self.parse(response.data, endpoint: endpoint, at: clock.now())
        guard !snapshot.balances.contains(where: { $0.currency.contains(key) }) else { throw UsageFailure.invalidResponse }
        return snapshot
    }
    static func validatedKey(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 4096,
              value.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 32 && $0.value < 127 }) else { throw UsageFailure.invalidCredential }
        return value
    }
    public static func parse(_ data: Data, endpoint: RelayEndpoint, at date: Date) throws -> RelaySnapshot {
        struct Amount: Decodable {
            let value: Decimal
            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                guard (try? container.decode(Bool.self)) == nil else { throw UsageFailure.invalidResponse }
                if let text = try? container.decode(String.self) {
                    guard text.count <= 128,
                          text.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
                          let parsed = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !parsed.isNaN else { throw UsageFailure.invalidResponse }
                    value = parsed
                } else {
                    let parsed = try container.decode(Decimal.self)
                    guard !parsed.isNaN else { throw UsageFailure.invalidResponse }
                    value = parsed
                }
            }
        }
        struct Quota: Decodable { let remaining: Amount?; let unit: String? }
        struct Payload: Decodable {
            let remaining: Amount?; let balance: Amount?; let quota: Quota?
            let unit: String?; let is_active: Bool?; let isValid: Bool?
        }
        do {
            guard data.count <= 1_048_576 else { throw UsageFailure.invalidResponse }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let amount = endpoint == .balance ? payload.balance : (payload.remaining ?? payload.quota?.remaining ?? payload.balance)
            let unit = endpoint == .balance ? "USD" : (payload.unit ?? payload.quota?.unit ?? "USD")
            guard let amount, !unit.isEmpty, unit.count <= 32,
                  unit.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value != 0x202E }) else { throw UsageFailure.invalidResponse }
            return RelaySnapshot(balances: [CurrencyBalance(currency: unit, total: amount.value)],
                isAvailable: endpoint == .balance ? payload.is_active : (payload.is_active ?? payload.isValid), fetchedAt: date)
        } catch { throw UsageFailure.invalidResponse }
    }
}
