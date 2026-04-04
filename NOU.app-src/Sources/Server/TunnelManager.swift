import Foundation

/// Manages a Cloudflare Tunnel (QUIC/HTTP3) for remote access to the local NOU server.
@MainActor
class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    @Published var tunnelURL: String? = nil
    @Published var isRunning: Bool = false

    private var process: Process?
    private var caffeinateProcess: Process?

    // MARK: - Auto-Start

    /// Auto-start tunnel if enabled in UserDefaults (call on app launch).
    func autoStart() {
        guard UserDefaults.standard.bool(forKey: "nou.tunnel.autostart") else { return }
        start()
    }

    var isAutoStartEnabled: Bool {
        UserDefaults.standard.bool(forKey: "nou.tunnel.autostart")
    }

    func setAutoStart(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "nou.tunnel.autostart")
        if enabled && !isRunning {
            start()
        } else if !enabled && isRunning {
            stop()
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        guard let binary = findCloudflared() else {
            print("[Tunnel] cloudflared not found. Install: brew install cloudflared")
            return
        }

        isRunning = true
        preventSleep()

        // Launch cloudflared in background (same pattern as existing MenubarController code)
        DispatchQueue.global().async { [weak self] in
            // Kill any existing cloudflared first
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            kill.arguments = ["-f", "cloudflared"]
            try? kill.run(); kill.waitUntilExit()
            sleep(1)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", "export PATH=/opt/homebrew/bin:$PATH && nohup \(binary) tunnel --url http://127.0.0.1:4001 --protocol quic > ~/cloudflared.log 2>&1 &"]
            try? proc.run()
            proc.waitUntilExit()

            // Poll for tunnel URL (up to 40 seconds)
            var url: String? = nil
            let home = FileManager.default.homeDirectoryForCurrentUser
            for _ in 0..<20 {
                sleep(2)
                if let log = try? String(contentsOf: home.appendingPathComponent("cloudflared.log"), encoding: .utf8),
                   let range = log.range(of: "https://[a-z0-9-]+\\.trycloudflare\\.com", options: .regularExpression) {
                    url = String(log[range])
                    break
                }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if let url {
                    self.tunnelURL = url
                    print("[Tunnel] Active (QUIC): \(url)")
                } else {
                    self.isRunning = false
                    self.allowSleep()
                    print("[Tunnel] Failed to start — no URL found in log")
                }
            }
        }
    }

    func stop() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "cloudflared"]
        try? p.run(); p.waitUntilExit()

        isRunning = false
        tunnelURL = nil
        allowSleep()
        print("[Tunnel] Stopped")
    }

    // MARK: - Status (for API endpoint)

    var statusJSON: [String: Any] {
        [
            "running": isRunning,
            "url": tunnelURL ?? NSNull(),
            "protocol": "quic",
            "auto_start": isAutoStartEnabled
        ]
    }

    // MARK: - Sleep Prevention

    private func preventSleep() {
        guard caffeinateProcess == nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-d", "-i", "-s"] // prevent display, idle, and system sleep
        try? p.run()
        caffeinateProcess = p
    }

    func allowSleep() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
    }

    // MARK: - Helpers

    private func findCloudflared() -> String? {
        let candidates = [
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "/usr/bin/cloudflared"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
