import Foundation

/// 仅提取本 App 已安装描述文件里的能力，不导出账号或设备列表。
public struct ProfileCapabilities: Sendable, Equatable {
    public enum ParseError: Error { case missingPropertyList, invalidProfile }
    public let applicationGroups: [String]
    public let identifierPrefixes: [String]

    public static func decode(_ data: Data) throws -> ProfileCapabilities {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            throw ParseError.missingPropertyList
        }
        let propertyList = data[start.lowerBound..<end.upperBound]
        guard let profile = try PropertyListSerialization.propertyList(from: Data(propertyList), format: nil) as? [String: Any],
              let entitlements = profile["Entitlements"] as? [String: Any] else {
            throw ParseError.invalidProfile
        }
        return ProfileCapabilities(
            applicationGroups: entitlements["com.apple.security.application-groups"] as? [String] ?? [],
            identifierPrefixes: profile["ApplicationIdentifierPrefix"] as? [String] ?? []
        )
    }

    public func matchingGroups(original: String) -> [String] {
        guard !original.isEmpty else { return [] }
        return applicationGroups.filter {
            $0 == original || $0.hasPrefix(original + ".") || $0.hasSuffix("." + original)
        }
    }
}
