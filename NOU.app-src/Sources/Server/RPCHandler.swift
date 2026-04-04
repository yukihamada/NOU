import Foundation
import Hummingbird

struct RPCHandler {

    /// GET /api/rpc/status — Current distributed inference status.
    static func handleStatus(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let di = DistributedInference.shared
        let status = await di.status()
        let result: [String: Any] = [
            "local_rpc_running": status.localRPCRunning,
            "local_rpc_port": status.localRPCPort,
            "distributed_enabled": status.distributedEnabled,
            "rpc_server_available": status.rpcServerAvailable,
            "llama_server_rpc_available": status.llamaServerRPCAvailable,
            "workers": status.workers.map { w in
                [
                    "host": w.host,
                    "port": w.port,
                    "status": w.status.rawValue,
                    "endpoint": w.endpoint,
                ] as [String: Any]
            }
        ]
        let data = try JSONSerialization.data(withJSONObject: result)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data)))
    }

    /// POST /api/rpc/start — Start the local RPC worker. Requires auth.
    /// Body (optional): { "port": 50052 }
    static func handleStartRPC(_ request: Request, _ context: some RequestContext) async throws -> Response {
        guard AuthCheck.isAuthorized(request: request) else {
            return Response(status: .unauthorized, headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"Not authorized"}"#)))
        }
        let di = DistributedInference.shared
        var port = 50052
        if let buf = try? await request.body.collect(upTo: 4096),
           let data = buf.getData(at: 0, length: buf.readableBytes),
           let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let p = body["port"] as? Int {
            port = p
        }
        let (ok, message) = await di.startLocalRPC(port: port)
        let result: [String: Any] = ["ok": ok, "message": message, "port": port]
        let data = try JSONSerialization.data(withJSONObject: result)
        return Response(status: ok ? .ok : .internalServerError,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data)))
    }

    /// POST /api/rpc/stop — Stop the local RPC worker. Requires auth.
    static func handleStopRPC(_ request: Request, _ context: some RequestContext) async throws -> Response {
        guard AuthCheck.isAuthorized(request: request) else {
            return Response(status: .unauthorized, headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"Not authorized"}"#)))
        }
        let di = DistributedInference.shared
        let message = await di.stopLocalRPC()
        let result: [String: Any] = ["ok": true, "message": message]
        let data = try JSONSerialization.data(withJSONObject: result)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data)))
    }

    /// POST /api/rpc/workers — Add a remote RPC worker.
    /// Body: { "host": "192.168.0.5", "port": 50052 }
    static func handleAddWorker(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let di = DistributedInference.shared
        let buf = try await request.body.collect(upTo: 4096)
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = body["host"] as? String else {
            let err = try JSONSerialization.data(withJSONObject: ["error": "Need host field"])
            return Response(status: .badRequest,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: err)))
        }
        let port = body["port"] as? Int ?? 50052
        await di.addWorker(host: host, port: port)
        await di.refreshWorkers()
        let status = await di.status()
        let result: [String: Any] = [
            "ok": true,
            "workers": status.workers.map { ["host": $0.host, "port": $0.port, "status": $0.status.rawValue] as [String: Any] }
        ]
        let out = try JSONSerialization.data(withJSONObject: result)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out)))
    }

    /// DELETE /api/rpc/workers — Remove a remote RPC worker.
    /// Body: { "host": "192.168.0.5", "port": 50052 }
    static func handleRemoveWorker(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let di = DistributedInference.shared
        let buf = try await request.body.collect(upTo: 4096)
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = body["host"] as? String else {
            let err = try JSONSerialization.data(withJSONObject: ["error": "Need host field"])
            return Response(status: .badRequest,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: err)))
        }
        let port = body["port"] as? Int ?? 50052
        await di.removeWorker(host: host, port: port)
        let result: [String: Any] = ["ok": true]
        let out = try JSONSerialization.data(withJSONObject: result)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out)))
    }

    /// POST /api/rpc/refresh — Probe all workers and update their status.
    static func handleRefresh(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let di = DistributedInference.shared
        await di.refreshWorkers()
        let status = await di.status()
        let result: [String: Any] = [
            "workers": status.workers.map { ["host": $0.host, "port": $0.port, "status": $0.status.rawValue] as [String: Any] }
        ]
        let data = try JSONSerialization.data(withJSONObject: result)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data)))
    }

    /// POST /api/rpc/enable — Enable or disable distributed mode. Requires auth.
    /// Body: { "enabled": true }
    static func handleEnable(_ request: Request, _ context: some RequestContext) async throws -> Response {
        guard AuthCheck.isAuthorized(request: request) else {
            return Response(status: .unauthorized, headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"Not authorized"}"#)))
        }
        let di = DistributedInference.shared
        let buf = try await request.body.collect(upTo: 4096)
        let body = (try? JSONSerialization.jsonObject(
            with: buf.getData(at: 0, length: buf.readableBytes) ?? Data()
        )) as? [String: Any]
        let enabled = body?["enabled"] as? Bool ?? true
        await di.setDistributedEnabled(enabled)
        let result: [String: Any] = ["ok": true, "distributed_enabled": enabled]
        let data = try JSONSerialization.data(withJSONObject: result)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data)))
    }
}
