import Testing
@testable import SearchKit

@Test func dependencyGraphWired() {
    #expect(SearchKitModule.coreDependency == "DocumentCore")
}
