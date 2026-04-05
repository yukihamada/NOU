import Foundation
import Hummingbird

/// HTTP endpoints for NOU node pairing.
struct PairingHandler {

    /// GET /api/pair/info — Returns this node's ID, name, and memory (public, no auth)
    static func handleInfo(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let nodeID = await PairingManager.shared.nodeID
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        let hostname = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let body: [String: Any] = [
            "node_id": nodeID,
            "name": hostname,
            "memory_gb": ramGB
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }

    /// POST /api/pair/request — Request pairing (body: {"node_id": "...", "name": "..."})
    /// Generates a PIN and shows it on screen. Does NOT return the PIN.
    static func handleRequest(_ request: Request, _ context: some RequestContext) async throws -> Response {
        // IP-based rate limit: max 10 requests per minute per source IP
        let sourceIP = AuthCheck.headerValue(request, name: "X-TCP-Remote-IP")
            ?? AuthCheck.headerValue(request, name: "Host")
            ?? "unknown"
        let rateLimited: Bool = pinLock.withLock {
            let now = Date()
            var entry = requestRateMap[sourceIP] ?? (count: 0, windowStart: now)
            if now.timeIntervalSince(entry.windowStart) > pairRequestWindow {
                entry = (count: 0, windowStart: now)  // reset window
            }
            entry.count += 1
            requestRateMap[sourceIP] = entry
            return entry.count > maxPairRequests
        }
        if rateLimited {
            return jsonResponse(status: .tooManyRequests, ["error": "Too many pairing requests. Try again later."])
        }

        let buf = try await request.body.collect(upTo: 10_000)
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let remoteNodeID = body["node_id"] as? String,
              let remoteName = body["name"] as? String else {
            return jsonResponse(status: .badRequest, ["error": "Missing node_id or name"])
        }

        // Check if already paired
        let alreadyPaired = await PairingManager.shared.isPaired(remoteNodeID)
        if alreadyPaired {
            return jsonResponse(status: .ok, ["status": "already_paired"])
        }

        // Generate PIN and show to user (fire-and-forget on MainActor)
        Task { @MainActor in
            _ = PairingManager.shared.handlePairRequest(remoteNodeID: remoteNodeID, remoteName: remoteName)
        }

        // Return immediately — PIN is shown on the target device's screen
        return jsonResponse(status: .ok, [
            "status": "pending",
            "message": "Check the screen on the target device for the PIN"
        ])
    }

    /// Rate limit state for PIN attempts and pairing requests (keyed by nodeID or IP)
    private static var pinAttempts: [String: (count: Int, lastAttempt: Date)] = [:]
    private static var requestRateMap: [String: (count: Int, windowStart: Date)] = [:]
    private static let pinLock = NSLock()
    private static let maxPinAttempts = 5
    private static let lockoutSeconds: TimeInterval = 300  // 5 min lockout
    private static let maxPairRequests = 10      // max pair requests per IP per window
    private static let pairRequestWindow: TimeInterval = 60  // 1 minute window

    /// POST /api/pair/confirm — Confirm pairing with PIN (body: {"node_id": "...", "pin": "123456"})
    static func handleConfirm(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let buf = try await request.body.collect(upTo: 10_000)
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let remoteNodeID = body["node_id"] as? String,
              let pin = body["pin"] as? String else {
            return jsonResponse(status: .badRequest, ["error": "Missing node_id or pin"])
        }

        // Rate limit: max 5 attempts per node_id, then 5-minute lockout
        let blocked: Bool = pinLock.withLock {
            let now = Date()
            if let entry = pinAttempts[remoteNodeID] {
                if entry.count >= maxPinAttempts && now.timeIntervalSince(entry.lastAttempt) < lockoutSeconds {
                    return true
                }
                if now.timeIntervalSince(entry.lastAttempt) >= lockoutSeconds {
                    pinAttempts[remoteNodeID] = nil  // Reset after lockout
                }
            }
            return false
        }
        if blocked {
            return jsonResponse(status: .tooManyRequests, ["error": "Too many attempts. Try again in 5 minutes."])
        }

        if let secret = await PairingManager.shared.confirmPairing(remoteNodeID: remoteNodeID, pin: pin) {
            pinLock.withLock { pinAttempts[remoteNodeID] = nil }  // Reset on success
            return jsonResponse(status: .ok, [
                "status": "paired",
                "secret": secret,
                "node_id": await PairingManager.shared.nodeID
            ])
        } else {
            // Increment failed attempt counter
            pinLock.withLock {
                let entry = pinAttempts[remoteNodeID] ?? (count: 0, lastAttempt: Date())
                pinAttempts[remoteNodeID] = (count: entry.count + 1, lastAttempt: Date())
            }
            // Delay response to slow down brute-force
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            return jsonResponse(status: .forbidden, [
                "status": "failed",
                "message": "Invalid or expired PIN"
            ])
        }
    }

    /// DELETE /api/pair/{nodeID} — Unpair a node (requires auth or local)
    static func handleUnpair(_ request: Request, _ context: some RequestContext) async throws -> Response {
        guard AuthCheck.isAuthorized(request: request) else {
            return jsonResponse(status: .unauthorized, ["error": "Not authorized"])
        }
        guard let targetID = context.parameters.get("nodeID") else {
            return jsonResponse(status: .badRequest, ["error": "Missing nodeID"])
        }
        await PairingManager.shared.unpair(targetID)
        return jsonResponse(status: .ok, ["status": "unpaired"])
    }

    // MARK: - Helpers

    private static func jsonResponse(status: HTTPResponse.Status, _ body: [String: Any]) -> Response {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data))
        )
    }
}
