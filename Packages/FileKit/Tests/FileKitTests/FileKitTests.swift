import Testing
@testable import FileKit

@Test func dependencyGraphWired() {
    #expect(FileKitModule.coreDependency == "DocumentCore")
}
