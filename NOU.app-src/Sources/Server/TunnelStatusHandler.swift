import Foundation
import Hummingbird

struct TunnelStatusHandler {
    static func handle(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let status = await TunnelManager.shared.statusJSON
        let body = try JSONSerialization.data(withJSONObject: status, options: [])
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: body))
        )
    }
}
