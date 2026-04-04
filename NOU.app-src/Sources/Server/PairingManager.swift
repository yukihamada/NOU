import AppKit
import Foundation
import CryptoKit

/// Manages secure pairing between NOU nodes (Bluetooth-style PIN exchange).
/// Stores paired node secrets in UserDefaults for persistent auto-reconnect.
@MainActor
class PairingManager {
    static let shared = PairingManager()

    /// This node's persistent unique ID
    let nodeID: String

    /// Paired nodes: [remoteNodeID: base64-encoded shared secret]
    private(set) var pairedNodes: [String: String]

    /// Pending incoming pairing requests: [remoteNodeID: pin]
    var pendingRequests: [String: String] = [:]

    private init() {
        if let id = UserDefaults.standard.string(forKey: "nou.node.id") {
            nodeID = id
        } else {
            let id = UUID().uuidString.lowercased()
            UserDefaults.standard.set(id, forKey: "nou.node.id")
            nodeID = id
        }
        pairedNodes = UserDefaults.standard.dictionary(forKey: "nou.paired.nodes") as? [String: String] ?? [:]
    }

    // MARK: - PIN Generation

    func generatePIN() -> String {
        String(format: "%06d", Int.random(in: 0...999999))
    }

    // MARK: - Incoming Pairing Request

    /// Handle an incoming pairing request from a remote node.
    /// Generates a PIN and shows it to the user via NSAlert.
    /// Returns the PIN (stored internally; NOT sent back to the requester).
    func handlePairRequest(remoteNodeID: String, remoteName: String) -> String {
        let pin = generatePIN()
        pendingRequests[remoteNodeID] = pin

        // Show PIN to user
        showPairingAlert(remoteName: remoteName, pin: pin)

        // Auto-expire after 60 seconds
        let capturedID = remoteNodeID
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.pendingRequests.removeValue(forKey: capturedID)
        }

        return pin
    }

    // MARK: - Confirm Pairing

    /// Confirm pairing with the given PIN. If correct, generates and stores a shared secret.
    /// Returns the base64-encoded secret on success, nil on failure.
    func confirmPairing(remoteNodeID: String, pin: String) -> String? {
        guard let expectedPIN = pendingRequests[remoteNodeID], expectedPIN == pin else {
            return nil
        }

        // Generate shared secret
        let secret = SymmetricKey(size: .bits256)
        let secretBase64 = secret.withUnsafeBytes { Data($0).base64EncodedString() }

        // Store pairing
        pairedNodes[remoteNodeID] = secretBase64
        savePairedNodes()
        pendingRequests.removeValue(forKey: remoteNodeID)

        return secretBase64
    }

    // MARK: - Store Remote Pairing

    /// Store a pairing secret received from the remote side after successful PIN confirmation.
    func storePairing(remoteNodeID: String, secret: String) {
        pairedNodes[remoteNodeID] = secret
        savePairedNodes()
    }

    // MARK: - Query

    func isPaired(_ nodeID: String) -> Bool {
        pairedNodes[nodeID] != nil
    }

    // MARK: - Token Generation (for outgoing requests)

    /// Generate a Bearer token for authenticated requests to a paired node.
    /// Format: "nodeID:timestamp.hmac"
    func generateToken(forNode targetNodeID: String) -> String? {
        guard let secretBase64 = pairedNodes[targetNodeID],
              let secretData = Data(base64Encoded: secretBase64) else { return nil }
        let key = SymmetricKey(data: secretData)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(timestamp.utf8), using: key)
        return "\(nodeID):\(timestamp).\(Data(mac).base64EncodedString())"
    }

    // MARK: - Token Validation (for incoming requests)

    /// Validate a Bearer token from a paired node.
    /// Token format: "nodeID:timestamp.hmac"
    nonisolated func validateToken(_ bearerValue: String) -> Bool {
        // Parse "nodeID:timestamp.hmac"
        guard let colonIdx = bearerValue.firstIndex(of: ":") else { return false }
        let remoteNodeID = String(bearerValue[bearerValue.startIndex..<colonIdx])
        let token = String(bearerValue[bearerValue.index(after: colonIdx)...])

        let parts = token.split(separator: ".")
        guard parts.count == 2,
              let timestamp = Int(parts[0]) else { return false }

        // Check timestamp within 5 minutes
        let now = Int(Date().timeIntervalSince1970)
        guard abs(now - timestamp) < 300 else { return false }

        // Look up secret from UserDefaults (thread-safe read)
        let paired = UserDefaults.standard.dictionary(forKey: "nou.paired.nodes") as? [String: String] ?? [:]
        guard let secretBase64 = paired[remoteNodeID],
              let secretData = Data(base64Encoded: secretBase64) else { return false }

        let key = SymmetricKey(data: secretData)
        let expectedMAC = HMAC<SHA256>.authenticationCode(for: Data(String(parts[0]).utf8), using: key)
        guard let macData = Data(base64Encoded: String(parts[1])) else { return false }
        return Data(expectedMAC) == macData
    }

    // MARK: - Unpair

    func unpair(_ nodeID: String) {
        pairedNodes.removeValue(forKey: nodeID)
        savePairedNodes()
    }

    // MARK: - Private

    private func savePairedNodes() {
        UserDefaults.standard.set(pairedNodes, forKey: "nou.paired.nodes")
    }

    private func showPairingAlert(remoteName: String, pin: String) {
        // Fully non-blocking: print to console + copy to clipboard
        print("[Pairing] 🔑 PIN: \(pin) (from \(remoteName))")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pin, forType: .string)
        // Show as a floating panel (not modal)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 140),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "NOU Pairing"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.center()
        let label = NSTextField(wrappingLabelWithString: "\(remoteName) wants to pair.\n\nPIN: \(pin)\n\nEnter this PIN on that device.")
        label.font = .systemFont(ofSize: 14)
        label.alignment = .center
        label.frame = NSRect(x: 20, y: 20, width: 280, height: 100)
        panel.contentView?.addSubview(label)
        panel.orderFront(nil)
        // Auto-close after 60 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { panel.close() }
    }
}

// Re-use the i18n helper from MenubarController
private func L(_ ja: String, _ en: String) -> String {
    Locale.current.language.languageCode?.identifier == "ja" ? ja : en
}
