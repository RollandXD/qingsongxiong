import BearPlatform
import Foundation
import Testing

@Test func readsOnlyMatchingGroupsFromSyntheticProfile() throws {
    let profile: [String: Any] = [
        "ApplicationIdentifierPrefix": ["EXAMPLE001"],
        "Entitlements": ["com.apple.security.application-groups": [
            "group.example.bear.EXAMPLE001", "group.unrelated.tool",
        ]],
    ]
    let xml = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    let cmsLike = Data([0x30, 0x82, 0x01, 0x00]) + xml + Data([0x00, 0x01])
    let decoded = try ProfileCapabilities.decode(cmsLike)
    #expect(decoded.identifierPrefixes == ["EXAMPLE001"])
    #expect(decoded.matchingGroups(original: "group.example.bear") == ["group.example.bear.EXAMPLE001"])
    #expect(decoded.matchingGroups(original: "") == [])
}
