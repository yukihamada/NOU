import Foundation
import Hummingbird

struct BlackboardHandler {

    /// GET /api/blackboard — List all entries (optionally ?prefix=X or ?tag=Y)
    static func handleList(_ request: Request, _ context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireAuth(request: request) { return deny }
        let prefix = request.uri.queryParameters.first(where: { $0.key == "prefix" }).map { String($0.value) }
        let tag    = request.uri.queryParameters.first(where: { $0.key == "tag" }).map { String($0.value) }
        let entries = await BlackboardStore.shared.list(
            prefix: prefix,
            tag: tag
        )
        let out = entries.map { e -> [String: Any] in
            var d: [String: Any] = [
                "key": e.key, "value": e.value, "author": e.author,
                "timestamp": e.timestamp, "tags": e.tags
            ]
            if let ttl = e.ttl { d["ttl"] = ttl }
            return d
        }
        let data = try JSONSerialization.data(withJSONObject: out)
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: .init(data: data)))
    }

    /// GET /api/blackboard/{key} — Get a single entry
    static func handleGet(_ request: Request, _ context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireAuth(request: request) { return deny }
        guard let key = context.parameters.get("key") else {
            return jsonErr(.badRequest, "Missing key")
        }
        guard let entry = await BlackboardStore.shared.get(key: key) else {
            return jsonErr(.notFound, "Key not found")
        }
        var d: [String: Any] = [
            "key": entry.key, "value": entry.value, "author": entry.author,
            "timestamp": entry.timestamp, "tags": entry.tags
        ]
        if let ttl = entry.ttl { d["ttl"] = ttl }
        let data = try JSONSerialization.data(withJSONObject: d)
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: .init(data: data)))
    }

    /// POST /api/blackboard/{key} — Set/update an entry
    /// Body: { "value": "...", "tags": ["agent","task"], "ttl": 3600 }
    static func handleSet(_ request: Request, _ context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireAuth(request: request) { return deny }
        guard let key = context.parameters.get("key") else {
            return jsonErr(.badRequest, "Missing key")
        }
        let buf = try await request.body.collect(upTo: 1_048_576) // 1MB max
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = body["value"] as? String else {
            return jsonErr(.badRequest, "Missing value in body")
        }
        let tags  = body["tags"] as? [String] ?? []
        let ttl   = body["ttl"] as? TimeInterval
        let author = body["author"] as? String ?? "local"

        await BlackboardStore.shared.set(key: key, value: value, author: author, tags: tags, ttl: ttl)

        let resp: [String: Any] = ["ok": true, "key": key]
        let out = try JSONSerialization.data(withJSONObject: resp)
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: .init(data: out)))
    }

    /// DELETE /api/blackboard/{key} — Delete an entry (local only)
    static func handleDelete(_ request: Request, _ context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }
        guard let key = context.parameters.get("key") else {
            return jsonErr(.badRequest, "Missing key")
        }
        await BlackboardStore.shared.delete(key: key)
        let out = try JSONSerialization.data(withJSONObject: ["ok": true])
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: .init(data: out)))
    }

    /// GET /api/blackboard/export — Full export for sync between nodes (auth required)
    static func handleExport(_ request: Request, _ context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireAuth(request: request) { return deny }
        let all = await BlackboardStore.shared.exportAll()
        let data = try JSONSerialization.data(withJSONObject: all)
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: .init(data: data)))
    }

    /// POST /api/blackboard/sync — Receive and merge entries from a remote node (auth required)
    static func handleSync(_ request: Request, _ context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireAuth(request: request) { return deny }
        let buf = try await request.body.collect(upTo: 10_485_760) // 10MB
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              let body = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return jsonErr(.badRequest, "Expected JSON array")
        }
        await BlackboardStore.shared.merge(remote: body)
        let out = try JSONSerialization.data(withJSONObject: ["ok": true, "merged": body.count])
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: .init(data: out)))
    }

    // MARK: - Helpers

    private static func jsonErr(_ status: HTTPResponse.Status, _ msg: String) -> Response {
        let d = (try? JSONSerialization.data(withJSONObject: ["error": msg])) ?? Data()
        return Response(status: status, headers: [.contentType: "application/json"],
                        body: .init(byteBuffer: .init(data: d)))
    }
}
