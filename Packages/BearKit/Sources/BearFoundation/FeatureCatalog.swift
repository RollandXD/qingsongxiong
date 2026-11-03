import Foundation

public struct FeatureDescriptor: Hashable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String

    public init(id: String, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

public struct FeatureRoute: Equatable, Sendable {
    public let featureID: String
    public let components: [String]
}

public struct FeatureCatalog: Sendable {
    public enum CatalogError: Error, Equatable {
        case invalidIdentifier(String)
        case duplicateIdentifier(String)
    }

    public let features: [FeatureDescriptor]

    public init(features: [FeatureDescriptor]) throws {
        var seen = Set<String>()
        for feature in features {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
            guard !feature.id.isEmpty, feature.id.count <= 48,
                  feature.id.unicodeScalars.allSatisfy(allowed.contains),
                  feature.id.first?.isLetter == true else {
                throw CatalogError.invalidIdentifier(feature.id)
            }
            guard seen.insert(feature.id).inserted else {
                throw CatalogError.duplicateIdentifier(feature.id)
            }
        }
        self.features = features
    }

    public func route(for url: URL, scheme: String) -> FeatureRoute? {
        guard url.scheme == scheme, url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil,
              let host = url.host, features.contains(where: { $0.id == host }) else { return nil }
        let components = url.path.split(separator: "/").map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return FeatureRoute(featureID: host, components: components)
    }
}
