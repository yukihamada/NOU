import Foundation
import Combine

/// ViewModel that polls the local NOU API for live stats and node info.
@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isOnline = false
    @Published var tokPerSec: Double = 0
    @Published var totalRequests: Int = 0
    @Published var uptimeSeconds: Int = 0
    @Published var totalTokensOut: Int = 0
    @Published var depinRequests: Int = 0

    @Published var localModels: [SlotInfo] = []
    @Published var memoryGB: Int = 0
    @Published var hostname: String = "This Mac"

    // Nodes from the browser (injected)
    @Published var nodes: [NOUNode] = []

    // Tunnel
    @Published var tunnelURL: String? = nil
    @Published var tunnelConnected: Bool = false

    private var refreshTask: Task<Void, Never>?
    private let baseURL = "http://127.0.0.1:4001"

    // MARK: - Lifecycle

    func startRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
            }
        }
    }

    func stopRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Refresh

    private func refresh() async {
        // Health
        let (healthy, mem, host) = await NOUAPIClient.healthDetailed(url: baseURL)
        isOnline = healthy
        if mem > 0 { memoryGB = mem }
        if !host.isEmpty { hostname = host }

        // Models
        localModels = await NOUAPIClient.models(url: baseURL)

        // Stats
        await fetchStats()

        // Tunnel
        await fetchTunnelStatus()
    }

    private func fetchStats() async {
        guard let url = URL(string: "\(baseURL)/api/stats") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            totalRequests = json["total_requests"] as? Int ?? 0
            depinRequests = json["depin_requests"] as? Int ?? 0
            totalTokensOut = json["total_tokens_out"] as? Int ?? 0
            uptimeSeconds = json["uptime_seconds"] as? Int ?? 0
            if let tpsStr = json["tok_per_sec"] as? String, let tps = Double(tpsStr) {
                tokPerSec = tps
            } else if let tps = json["tok_per_sec"] as? Double {
                tokPerSec = tps
            }
        } catch {}
    }

    private func fetchTunnelStatus() async {
        guard let url = URL(string: "\(baseURL)/api/tunnel/status") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                tunnelConnected = false
                tunnelURL = nil
                return
            }
            tunnelConnected = json["connected"] as? Bool ?? false
            tunnelURL = json["url"] as? String
        } catch {
            tunnelConnected = false
            tunnelURL = nil
        }
    }

    // MARK: - Computed

    var localTier: NodeTier { NodeTier.from(memoryGB: memoryGB) }

    var uptimeFormatted: String {
        let h = uptimeSeconds / 3600
        let m = (uptimeSeconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(uptimeSeconds)s"
    }
}
