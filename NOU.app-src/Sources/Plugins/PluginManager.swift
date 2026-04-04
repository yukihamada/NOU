import Foundation

struct ToolPlugin {
    let name: String
    let description: String
    let parameters: [String: Any]  // JSON Schema
    let execute: @Sendable ([String: Any]) async -> String
    var enabled: Bool
}

final class PluginManager: @unchecked Sendable {
    static let shared = PluginManager()

    private let lock = NSLock()
    private var _plugins: [String: ToolPlugin] = [:]

    var plugins: [String: ToolPlugin] {
        get { lock.withLock { _plugins } }
        set { lock.withLock { _plugins = newValue } }
    }

    init() {
        registerBuiltins()
    }

    private func registerBuiltins() {
        _plugins["web_search"] = ToolPlugin(
            name: "web_search",
            description: "Search the web for current information. Use this when you need up-to-date facts.",
            parameters: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "The search query"] as [String: Any]
                ] as [String: Any],
                "required": ["query"]
            ] as [String: Any],
            execute: { args in await WebSearchPlugin.execute(args) },
            enabled: true
        )

        _plugins["run_code"] = ToolPlugin(
            name: "run_code",
            description: "Execute code in a sandboxed environment. Supports Python and shell commands.",
            parameters: [
                "type": "object",
                "properties": [
                    "language": ["type": "string", "enum": ["python", "shell"], "description": "Programming language"] as [String: Any],
                    "code": ["type": "string", "description": "The code to execute"] as [String: Any]
                ] as [String: Any],
                "required": ["language", "code"]
            ] as [String: Any],
            execute: { args in await CodeExecutionPlugin.execute(args) },
            enabled: true
        )

        _plugins["generate_image"] = ToolPlugin(
            name: "generate_image",
            description: "Generate an image from a text description using Stable Diffusion.",
            parameters: [
                "type": "object",
                "properties": [
                    "prompt": ["type": "string", "description": "Image description"] as [String: Any],
                    "style": ["type": "string", "enum": ["realistic", "artistic", "anime"], "description": "Image style"] as [String: Any]
                ] as [String: Any],
                "required": ["prompt"]
            ] as [String: Any],
            execute: { args in await ImageGenPlugin.execute(args) },
            enabled: false  // Disabled by default, needs sd model
        )
    }

    /// Get enabled plugins as OpenAI tools format
    func toolDefinitions() -> [[String: Any]] {
        lock.withLock {
            _plugins.values.filter { $0.enabled }.map { plugin in
                [
                    "type": "function",
                    "function": [
                        "name": plugin.name,
                        "description": plugin.description,
                        "parameters": plugin.parameters
                    ] as [String: Any]
                ]
            }
        }
    }

    /// Execute a tool call
    func execute(name: String, arguments: [String: Any]) async -> String {
        let plugin = lock.withLock { _plugins[name] }
        guard let plugin, plugin.enabled else {
            return "Error: Tool '\(name)' not found or not enabled"
        }
        return await plugin.execute(arguments)
    }

    /// Toggle a plugin on/off, returns new state
    func toggle(name: String) -> Bool? {
        lock.withLock {
            guard _plugins[name] != nil else { return nil }
            _plugins[name]!.enabled.toggle()
            return _plugins[name]!.enabled
        }
    }

    /// List all plugins as JSON-serializable dictionaries
    func listPlugins() -> [[String: Any]] {
        lock.withLock {
            _plugins.values.map { p in
                [
                    "name": p.name,
                    "description": p.description,
                    "enabled": p.enabled,
                    "parameters": p.parameters
                ] as [String: Any]
            }
        }
    }
}
