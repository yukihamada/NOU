import Foundation
import Hummingbird
import CryptoKit

/// Simple authentication checker for NOU node requests.
/// Local requests are always allowed. Remote requests require a valid pairing token.
enum AuthCheck {

    /// Check if a request is authorized (local OR valid pairing token).
    static func isAuthorized(request: Request) -> Bool {
        // Local requests are always allowed
        if isLocal(request) { return true }

        // Check existing DePIN API key auth (backwards compatible)
        if checkDepinAuth(request) { return true }

        // Check pairing token
        return validatePairingToken(request)
    }

    /// Check if request is from localhost (no proxy headers).
    static func isLocal(_ request: Request) -> Bool {
        let hasForwarded = headerValue(request, name: "X-Forwarded-For").map { !$0.hasPrefix("127.") } ?? false
        let hasCF = headerValue(request, name: "CF-Connecting-IP") != nil
        return !hasForwarded && !hasCF
    }

    // MARK: - Private

    private static func headerValue(_ request: Request, name: String) -> String? {
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

        // Parse "nodeID:timestamp.hmac"
        guard let colonIdx = bearer.firstIndex(of: ":") else { return false }
        let remoteNodeID = String(bearer[bearer.startIndex..<colonIdx])
        let token = String(bearer[bearer.index(after: colonIdx)...])

        let parts = token.split(separator: ".")
        guard parts.count == 2,
              let timestamp = Int(parts[0]) else { return false }

        // Timestamp must be within 5 minutes
        let now = Int(Date().timeIntervalSince1970)
        guard abs(now - timestamp) < 300 else { return false }

        // Look up shared secret from UserDefaults (thread-safe)
        let paired = UserDefaults.standard.dictionary(forKey: "nou.paired.nodes") as? [String: String] ?? [:]
        guard let secretBase64 = paired[remoteNodeID],
              let secretData = Data(base64Encoded: secretBase64) else { return false }

        // Verify HMAC
        let key = SymmetricKey(data: secretData)
        let expectedMAC = HMAC<SHA256>.authenticationCode(for: Data(String(parts[0]).utf8), using: key)
        guard let macData = Data(base64Encoded: String(parts[1])) else { return false }
        return Data(expectedMAC) == macData
    }

    /// Check DePIN API key (existing auth, backwards compatible)
    private static func checkDepinAuth(_ request: Request) -> Bool {
        if let storedKey = UserDefaults.standard.string(forKey: "nou.depin.apiKey"),
           !storedKey.isEmpty {
            let authHeader = headerValue(request, name: "Authorization") ?? ""
            if authHeader.hasPrefix("Bearer ") {
                return String(authHeader.dropFirst(7)) == storedKey
            }
        }
        return false
    }
}
