import BearFoundation
import Foundation

/// 首页可以放的主卡来源：已连接的厂商账户，或某个中转账户。
///
/// 不复用 `ProviderID`：中转不是厂商，不能被伪装成 `.claude`；也用稳定 UUID
/// 而不是名称，改名不丢选择，删除后只留空位，不偷偷换成别的账号。
public enum AccountRef: Codable, Equatable, Hashable, Sendable {
    case provider(ProviderID)
    case relay(UUID)

    /// 显式编码，不用合成 `_0` 之类的键：写进本地文件后要能读、能核对、能长期演进。
    private enum CodingKeys: String, CodingKey { case kind, provider, id }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .provider(let provider):
            try container.encode("provider", forKey: .kind)
            try container.encode(provider, forKey: .provider)
        case .relay(let id):
            try container.encode("relay", forKey: .kind)
            try container.encode(id, forKey: .id)
        }
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "provider": self = .provider(try values.decode(ProviderID.self, forKey: .provider))
        case "relay": self = .relay(try values.decode(UUID.self, forKey: .id))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values,
                                                        debugDescription: "未知的主卡类型")
        }
    }

    public var id: String {
        switch self {
        case .provider(let provider): "provider:" + provider.rawValue
        case .relay(let id): "relay:" + id.uuidString
        }
    }

    public var providerID: ProviderID? {
        switch self {
        case .provider(let provider): provider
        case .relay: nil
        }
    }

    public var relayID: UUID? {
        switch self {
        case .provider: nil
        case .relay(let id): id
        }
    }

    public var isRelay: Bool { relayID != nil }
}

/// 首页两张主卡的选择与顺序。位置固定两名，空位表示用户还没选。
public struct DashboardPreferences: TimestampedRecord, Equatable, Sendable {
    /// 首页主卡数量；两张同级，不设“主/次”。
    public static let slotCount = 2
    public static let schemaRevision = 1
    /// 首次安装沿用 0.4 的顺序，用户可自由替换或交换。
    public static let defaultCards: [AccountRef?] = [.provider(.codex), .provider(.claude)]

    public let revision: Int
    /// 恰好 `slotCount` 个位置；空位为 `nil`。
    public let cards: [AccountRef?]
    public let updatedAt: Date

    public init(cards: [AccountRef?], updatedAt: Date, revision: Int = DashboardPreferences.schemaRevision) {
        self.cards = Self.normalized(cards)
        self.updatedAt = updatedAt
        self.revision = revision
    }

    public static func initial(at date: Date) -> DashboardPreferences {
        DashboardPreferences(cards: defaultCards, updatedAt: date)
    }

    private enum CodingKeys: String, CodingKey { case revision, cards, updatedAt }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(cards: try values.decode([AccountRef?].self, forKey: .cards),
                  updatedAt: try values.decode(Date.self, forKey: .updatedAt),
                  revision: try values.decodeIfPresent(Int.self, forKey: .revision) ?? Self.schemaRevision)
    }

    /// 固定长度、去掉重复项；坏文件或手改过的长度都不能让首页崩掉或出现同一账户两次。
    private static func normalized(_ cards: [AccountRef?]) -> [AccountRef?] {
        var seen = Set<AccountRef>()
        var result: [AccountRef?] = []
        for card in cards.prefix(slotCount) {
            guard let card else { result.append(nil); continue }
            guard seen.insert(card).inserted else { result.append(nil); continue }
            result.append(card)
        }
        while result.count < slotCount { result.append(nil) }
        return result
    }

    public func ref(atSlot index: Int) -> AccountRef? {
        cards.indices.contains(index) ? cards[index] : nil
    }

    /// 把某个位置换成 `ref`；若 `ref` 已在另一位置，则两位置互换，绝不出现重复。
    public func setting(_ ref: AccountRef?, atSlot index: Int, at date: Date) -> DashboardPreferences {
        guard cards.indices.contains(index) else { return self }
        var next = cards
        if let ref, let existing = next.firstIndex(of: ref), existing != index {
            let displaced = next[index]
            next[existing] = displaced
        }
        next[index] = ref
        return DashboardPreferences(cards: next, updatedAt: date)
    }

    public func swapping(_ first: Int, _ second: Int, at date: Date) -> DashboardPreferences {
        guard cards.indices.contains(first), cards.indices.contains(second), first != second else { return self }
        var next = cards
        next.swapAt(first, second)
        return DashboardPreferences(cards: next, updatedAt: date)
    }

    /// 中转账户被删除时清掉指向它的位置，其他位置保持原样。
    public func removingRelay(_ id: UUID, at date: Date) -> DashboardPreferences {
        guard cards.contains(.relay(id)) else { return self }
        return DashboardPreferences(cards: cards.map { $0 == .relay(id) ? nil : $0 }, updatedAt: date)
    }

    public var selectedRefs: [AccountRef] { cards.compactMap { $0 } }
}
