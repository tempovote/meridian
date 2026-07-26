import Foundation

/// Definition of a custom command exposed by a Meridian plugin.
public struct PluginCommandDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        identifier
    }

    public let identifier: String
    public let title: String
    public let keyEquivalent: String?
    public let scriptPath: String?

    public init(identifier: String, title: String, keyEquivalent: String? = nil, scriptPath: String? = nil) {
        self.identifier = identifier
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.scriptPath = scriptPath
    }
}

/// Declarative metadata manifest for a Meridian plugin (`plugin.json`).
public struct PluginManifest: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        identifier
    }

    public let identifier: String
    public let name: String
    public let version: String
    public let author: String
    public let description: String
    public let commands: [PluginCommandDefinition]

    public init(
        identifier: String,
        name: String,
        version: String,
        author: String,
        description: String,
        commands: [PluginCommandDefinition] = [],
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.commands = commands
    }
}
