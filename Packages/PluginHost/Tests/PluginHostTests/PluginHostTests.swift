import Testing
@testable import PluginHost

@Test func dependencyGraphWired() {
    #expect(PluginHostModule.apiDependency == "PluginAPI")
}
