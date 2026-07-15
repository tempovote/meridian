import Testing
@testable import SyntaxKit

@Test func dependencyGraphWired() {
    #expect(SyntaxKitModule.coreDependency == "DocumentCore")
}
