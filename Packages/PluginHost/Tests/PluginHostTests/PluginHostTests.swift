import Foundation
import PluginAPI
import PluginHost
import Testing

@Suite("PluginHostTests")
struct PluginHostTests {
    @Test func registerAndLoadPlugin() async {
        let manifest = PluginManifest(
            identifier: "dev.meridian.sample",
            name: "Sample Plugin",
            version: "1.0.0",
            author: "Meridian Team",
            description: "A test plugin for Meridian",
            commands: [
                PluginCommandDefinition(identifier: "sample.hello", title: "Say Hello"),
            ],
        )

        let engine = PluginHostEngine()
        let plugin = LoadedPlugin(manifest: manifest, pluginDirectory: FileManager.default.temporaryDirectory)
        await engine.register(plugin: plugin)

        let plugins = await engine.loadedPlugins()
        #expect(plugins.count == 1)
        #expect(plugins[0].manifest.identifier == "dev.meridian.sample")
    }
}
