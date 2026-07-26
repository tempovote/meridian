import Foundation
import PluginAPI

/// Represents an active loaded plugin instance.
public struct LoadedPlugin: Identifiable, Sendable, Equatable {
    public var id: String {
        manifest.identifier
    }

    public let manifest: PluginManifest
    public let pluginDirectory: URL

    public init(manifest: PluginManifest, pluginDirectory: URL) {
        self.manifest = manifest
        self.pluginDirectory = pluginDirectory
    }
}

/// Managing host engine actor that discovers, registers, and runs Meridian plugins.
public actor PluginHostEngine {
    public static let shared = PluginHostEngine()
    private var registeredPlugins: [String: LoadedPlugin] = [:]

    public init() {}

    public func register(plugin: LoadedPlugin) {
        registeredPlugins[plugin.manifest.identifier] = plugin
    }

    public func unregister(pluginID: String) {
        registeredPlugins.removeValue(forKey: pluginID)
    }

    public func loadedPlugins() -> [LoadedPlugin] {
        Array(registeredPlugins.values)
    }

    public func loadPlugin(from directoryURL: URL) throws -> LoadedPlugin {
        let manifestURL = directoryURL.appendingPathComponent("plugin.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        let loaded = LoadedPlugin(manifest: manifest, pluginDirectory: directoryURL)
        register(plugin: loaded)
        return loaded
    }
}
