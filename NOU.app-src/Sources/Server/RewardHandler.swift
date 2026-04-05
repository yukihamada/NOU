import Foundation
import Hummingbird

enum RewardHandler {

    /// GET /api/rewards — returns compute units and wallet info
    static func handle(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }
        let snap = await RewardLedger.shared.snapshot()
        let out = try JSONSerialization.data(withJSONObject: snap)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out))
        )
    }

    /// POST /api/rewards/wallet   body: {"wallet":"<solana_address>"}
    static func handleSetWallet(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }
        let buf = try await request.body.collect(upTo: 65_536)
        guard let json = try? JSONSerialization.jsonObject(with: Data(buffer: buf)) as? [String: Any],
              let wallet = json["wallet"] as? String, !wallet.isEmpty else {
            return Response(
                status: .badRequest,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"wallet required"}"#))
            )
        }
        await RewardLedger.shared.setWallet(wallet)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: #"{"ok":true}"#))
        )
    }

    /// POST /api/rewards/mode   body: {"mode":"japan"} or {"mode":"global"}
    static func handleSetMode(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }
        let buf = try await request.body.collect(upTo: 65_536)
        guard let json = try? JSONSerialization.jsonObject(with: Data(buffer: buf)) as? [String: Any],
              let mode = json["mode"] as? String else {
            return Response(status: .badRequest, headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"mode required"}"#)))
        }
        await RewardLedger.shared.setJapanMode(mode == "japan")
        return Response(status: .ok, headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: #"{"ok":true}"#)))
    }
}
