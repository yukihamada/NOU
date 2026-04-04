import Foundation
import Hummingbird

/// Shared store for discovered network nodes — updated by NOUBrowser, read by API.
actor DiscoveredNodeStore {
    static let shared = DiscoveredNodeStore()

    private var _nodes: [[String: Any]] = []

    func update(_ nodes: [[String: Any]]) {
        _nodes = nodes
    }

    func snapshot() -> [[String: Any]] { _nodes }
}

struct NodesHandler {
    static func handle(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let nodes = await DiscoveredNodeStore.shared.snapshot()
        let body = try JSONSerialization.data(withJSONObject: nodes)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: body))
        )
    }
}
