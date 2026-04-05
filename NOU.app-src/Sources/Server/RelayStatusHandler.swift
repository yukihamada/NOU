import Foundation
import Hummingbird

enum RelayStatusHandler {

    /// GET /api/relay/status
    static func handle(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }
        var snap = await RelayClient.shared.snapshot
        snap["auto_connect"] = UserDefaults.standard.bool(forKey: "nou.relay.autoConnect")
        let data = try JSONSerialization.data(withJSONObject: snap)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data)))
    }

    /// POST /api/relay/connect
    static func handleConnect(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }
        await RelayClient.shared.connect()
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: #"{"ok":true}"#)))
    }

    /// POST /api/relay/disconnect
    static func handleDisconnect(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }
        await RelayClient.shared.disconnect()
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: #"{"ok":true}"#)))
    }

    /// POST /api/relay/auto-connect — toggle auto-connect on startup
    static func handleAutoConnect(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }
        let buf = try await request.body.collect(upTo: 1_000)
        let enabled: Bool
        if let data = buf.getData(at: 0, length: buf.readableBytes),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = json["enabled"] as? Bool {
            enabled = e
        } else {
            enabled = false
        }
        UserDefaults.standard.set(enabled, forKey: "nou.relay.autoConnect")
        let out = try JSONSerialization.data(withJSONObject: ["ok": true, "auto_connect": enabled])
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out)))
    }
}
