import Foundation
import Hummingbird
import CryptoKit
import Darwin

/// Simple authentication checker for NOU node requests.
/// Local requests are always allowed. Remote requests require a valid pairing token.
enum AuthCheck {

    /// Check if a request is authorized (local OR valid pairing token).
    static func isAuthorized(request: Request) -> Bool {
        if isLocal(request) { return true }
        if checkDepinAuth(request) { return true }
        return validatePairingToken(request)
    }

    // MARK: - Own IP cache (populated at first call)

    /// All IP addresses this machine is reachable on (loopback + LAN interfaces).
    /// Used to allow dashboard/API access via our own LAN IP, not just "localhost".
    static let ownIPs: Set<String> = {
        var ips: Set<String> = ["127.0.0.1", "::1", "localhost", "0.0.0.0"]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return ips }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addrPtr = cur.pointee.ifa_addr else { continue }
            let family = Int32(addrPtr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(family == AF_INET
                ? MemoryLayout<sockaddr_in>.size
                : MemoryLayout<sockaddr_in6>.size)
            if getnameinfo(addrPtr, len, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: buf)
                // strip IPv6 zone ID suffix (e.g. "fe80::1%lo0" → "fe80::1")
                ips.insert(ip.components(separatedBy: "%").first ?? ip)
            }
        }
        return ips
    }()

    /// Check if a request is from localhost or from one of this machine's own IP addresses.
    /// This allows dashboard/API access both via "localhost" AND via the LAN IP
    /// (e.g. http://192.168.0.194:4001), which macOS Safari and other apps may use.
    ///
    /// SECURITY: We still hard-deny if CDN/proxy headers are present, because those
    /// mean the request traversed the internet (Cloudflare Tunnel etc.).
    static func isLocal(_ request: Request) -> Bool {
        // Hard deny: relay-forwarded requests are not local even if Host=127.0.0.1
        if headerValue(request, name: "X-NOU-Source") == "relay" { return false }

        // Hard deny: CDN indicates request came through the internet
        if headerValue(request, name: "CF-Connecting-IP") != nil { return false }

        // Trusted TCP source IP (injected by RemoteIPMiddleware from NIO channel — cannot be spoofed)
        // If present and not a loopback/own IP, deny immediately
        if let tcpIP = headerValue(request, name: "X-TCP-Remote-IP") {
            return ownIPs.contains(tcpIP)
        }

        // Hard deny: non-loopback X-Forwarded-For means a reverse proxy forwarded it
        if let fwd = headerValue(request, name: "X-Forwarded-For") {
            let firstHop = fwd.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? fwd
            if firstHop != "127.0.0.1" && firstHop != "::1" { return false }
        }

        // X-Real-IP set by Nginx/other proxies
        if let ip = headerValue(request, name: "X-Real-IP") {
            return ownIPs.contains(ip)
        }

        // Host header: allow localhost, 127.x, ::1, OR any of our own LAN IPs
        if let host = headerValue(request, name: "Host") {
            // Strip port: "192.168.0.194:4001" → "192.168.0.194"
            let h: String
            if host.contains("[") {
                // IPv6 literal: "[fe80::1]:4001" → "fe80::1"
                h = host.components(separatedBy: "]").first.map { String($0.dropFirst()) } ?? host
            } else {
                h = host.split(separator: ":").first.map(String.init) ?? host
            }
            return ownIPs.contains(h)
        }

        // No Host header and no proxy headers → internal loopback (e.g. URLSession from within the app)
        return true
    }

    /// Require local-only access. Returns 403 response if not local.
    static func requireLocal(request: Request) -> Response? {
        if isLocal(request) { return nil }
        return Response(
            status: .forbidden,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: #"{"error":"This endpoint requires local access"}"#))
        )
    }

    /// Require authenticated access (local OR valid token). Returns 401 if not authorized.
    static func requireAuth(request: Request) -> Response? {
        if isAuthorized(request: request) { return nil }
        return Response(
            status: .unauthorized,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(string: #"{"error":"Authentication required"}"#))
        )
    }

    // MARK: - Private helpers

    static func headerValue(_ request: Request, name: String) -> String? {
        request.headers.first(where: {
            $0.name.rawName.caseInsensitiveCompare(name) == .orderedSame
        })?.value
    }

    /// Validate a pairing Bearer token.
    /// Token format in header: "Bearer nodeID:timestamp.hmac"
    private static func validatePairingToken(_ request: Request) -> Bool {
        guard let auth = headerValue(request, name: "Authorization"),
              auth.hasPrefix("Bearer ") else { return false }
        let bearer = String(auth.dropFirst(7))

        guard let colonIdx = bearer.firstIndex(of: ":") else { return false }
        let remoteNodeID = String(bearer[bearer.startIndex..<colonIdx])
        let token = String(bearer[bearer.index(after: colonIdx)...])

        let parts = token.split(separator: ".")
        guard parts.count == 2,
              let timestamp = Int(parts[0]) else { return false }

        // Timestamp must be within 5 minutes
        let now = Int(Date().timeIntervalSince1970)
        guard abs(now - timestamp) < 300 else { return false }

        let paired = UserDefaults.standard.dictionary(forKey: "nou.paired.nodes") as? [String: String] ?? [:]
        guard let secretBase64 = paired[remoteNodeID],
              let secretData = Data(base64Encoded: secretBase64) else { return false }

        let key = SymmetricKey(data: secretData)
        guard let macData = Data(base64Encoded: String(parts[1])) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(macData, authenticating: Data(String(parts[0]).utf8), using: key)
    }

    /// Check DePIN API key — constant-time comparison to prevent timing attacks
    private static func checkDepinAuth(_ request: Request) -> Bool {
        if let storedKey = UserDefaults.standard.string(forKey: "nou.depin.apiKey"),
           !storedKey.isEmpty {
            let authHeader = headerValue(request, name: "Authorization") ?? ""
            if authHeader.hasPrefix("Bearer ") {
                return timingSafeEqual(String(authHeader.dropFirst(7)), storedKey)
            }
        }
        return false
    }

    /// Constant-time string comparison — prevents timing attacks on secret values.
    static func timingSafeEqual(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(aBytes, bBytes) { result |= x ^ y }
        return result == 0
    }
}
