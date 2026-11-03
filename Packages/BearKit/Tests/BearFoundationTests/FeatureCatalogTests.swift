import BearFoundation
import Foundation
import Testing

@Test func rejectsDuplicateFeatures() throws {
    let descriptor = FeatureDescriptor(id: "notes", title: "笔记", systemImage: "note")
    #expect(throws: FeatureCatalog.CatalogError.duplicateIdentifier("notes")) {
        try FeatureCatalog(features: [descriptor, descriptor])
    }
}

@Test func featureRoutesDoNotKnowBusinessProviders() throws {
    let catalog = try FeatureCatalog(features: [FeatureDescriptor(id: "local-counter", title: "计数", systemImage: "plus")])
    let route = catalog.route(for: URL(string: "qingsongxiong://local-counter/increment")!, scheme: "qingsongxiong")
    #expect(route?.featureID == "local-counter")
    #expect(route?.components == ["increment"])
    #expect(catalog.route(for: URL(string: "https://local-counter/increment")!, scheme: "qingsongxiong") == nil)
    #expect(catalog.route(for: URL(string: "qingsongxiong://unknown/increment")!, scheme: "qingsongxiong") == nil)
    #expect(catalog.route(for: URL(string: "qingsongxiong://local-counter/increment?token=ignored")!, scheme: "qingsongxiong") == nil)
}
