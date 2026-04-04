import Foundation
import Hummingbird
import NIOCore

struct PluginHandler {
    /// GET /api/plugins — list all plugins and their status
    static func handleList(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let plugins = PluginManager.shared.listPlugins()
        let data = try JSONSerialization.data(withJSONObject: ["plugins": plugins])
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: .init(data: data)))
    }

    /// POST /api/plugins/{name}/toggle — enable/disable a plugin
    static func handleToggle(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let name = context.parameters.get("name") ?? ""
        guard !name.isEmpty else {
            return Response(status: .badRequest, headers: [.contentType: "application/json"],
                            body: .init(byteBuffer: .init(string: #"{"error":"Missing plugin name"}"#)))
        }
        guard let newState = PluginManager.shared.toggle(name: name) else {
            return Response(status: .notFound, headers: [.contentType: "application/json"],
                            body: .init(byteBuffer: .init(string: #"{"error":"Plugin not found"}"#)))
        }
        let resp: [String: Any] = ["name": name, "enabled": newState]
        let data = try JSONSerialization.data(withJSONObject: resp)
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: .init(data: data)))
    }
}
