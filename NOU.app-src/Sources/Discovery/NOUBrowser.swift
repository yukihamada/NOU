import Foundation
import Network

// MARK: - Node Tier (tree metaphor based on memory)

enum NodeTier: String {
    case seed   = "Seed"    // ≤8GB  (iPhone, small devices)
    case branch = "Branch"  // ≤24GB (MacBook Air, base models)
    case trunk  = "Trunk"   // ≤96GB (MacBook Pro, Mac Mini)
    case root   = "Root"    // >96GB (Mac Studio, Mac Pro, M5 Max)

    var icon: String {
        switch self {
        case .seed:   return "🌱"
        case .branch: return "🌿"
        case .trunk:  return "🌳"
        case .root:   return "🌲"
        }
    }

    var label: String { "\(icon) \(rawValue)" }

    static func from(memoryGB: Int) -> NodeTier {
        switch memoryGB {
        case ...8:   return .seed
        case ...24:  return .branch
        case ...96:  return .trunk
        default:     return .root
        }
    }
}

/// A discovered NOU node on the network.
struct NOUNode {
    var name: String
    var url: String           // e.g. "http://192.168.0.5:4001"
    var nodeID: String = ""   // remote node's unique ID (from /api/pair/info)
    var models: [SlotInfo] = []
    var healthy: Bool = false
    var isLocal: Bool = false  // true if this is localhost/self
    var rpcAvailable: Bool = false
    var memoryGB: Int = 0     // physical RAM in GB
    var paired: Bool = false  // true if securely paired
    var tier: NodeTier { NodeTier.from(memoryGB: memoryGB) }
    var tierLabel: String { memoryGB > 0 ? "\(tier.icon) \(tier.rawValue) (\(memoryGB)GB)" : tier.icon }
}

struct SlotInfo {
    var name: String      // "main", "fast", "vision"
    var label: String
    var model: String
    var port: Int
    var runtime: String   // "mlx" or "llamacpp"
    var running: Bool
}

/// Discovers NOU nodes on the local network via Bonjour + fallback probing.
@MainActor
final class NOUBrowser: ObservableObject {
    @Published var nodes: [NOUNode] = []
    @Published var isSearching: Bool = false

    private var browser: NWBrowser?
    private var probeTask: Task<Void, Never>?
    private var refreshTimer: Timer?

    // Known hosts to always probe (user-configurable)
    private var manualHosts: [String] {
        get { UserDefaults.standard.stringArray(forKey: "nou.browser.hosts") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "nou.browser.hosts") }
    }

    private let defaultProbeHosts = [
        "http://localhost:4001",
    ]

    // MARK: - Start / Stop

    func start() {
        guard !isSearching else { return }
        isSearching = true
        startBonjourBrowser()
        refreshAllNodes()

        // Periodic refresh every 10 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAllNodes()
            }
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        probeTask?.cancel()
        probeTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        isSearching = false
    }

    func addManualHost(_ url: String) {
        var hosts = manualHosts
        if !hosts.contains(url) {
            hosts.append(url)
            manualHosts = hosts
        }
        // Add immediately and refresh
        if !nodes.contains(where: { $0.url == url }) {
            nodes.append(NOUNode(name: hostLabel(url), url: url))
        }
        refreshAllNodes()
    }

    // MARK: - Bonjour

    private func startBonjourBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjour(type: "_nou._tcp", domain: "local."), using: params)

        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                if case .failed = state {
                    self?.browser = nil
                    print("[NOUBrowser] Bonjour browser failed")
                }
            }
        }

        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.resolveService(name: name, endpoint: result.endpoint)
                    }
                }
            }
        }

        b.start(queue: .main)
        browser = b
    }

    private func resolveService(name: String, endpoint: NWEndpoint) {
        // Use NetService to resolve to a proper hostname (avoids IPv6 link-local issues)
        let resolver = BonjourResolver(name: name) { [weak self] hostname in
            guard let self, let hostname else { return }
            let url = "http://\(hostname):4001"
            if !self.nodes.contains(where: { $0.url == url }) {
                self.nodes.append(NOUNode(name: name, url: url))
                self.refreshAllNodes()
            }
        }
        resolver.start()
        // Keep reference alive
        activeResolvers.append(resolver)
    }

    private var activeResolvers: [BonjourResolver] = []

    // MARK: - Refresh

    func refreshAllNodes() {
        // Ensure default + manual hosts are in the list
        let allHosts = Set(defaultProbeHosts + manualHosts)
        for host in allHosts {
            if !nodes.contains(where: { $0.url == host }) {
                nodes.append(NOUNode(name: hostLabel(host), url: host))
            }
        }

        // Refresh each node
        for i in nodes.indices {
            let url = nodes[i].url
            let index = i
            Task {
                let status = await NOUAPIClient.fetchNodeStatus(url: url)
                let rpcAvailable = await NOUAPIClient.probeRPCWorker(url: url)
                await MainActor.run { [weak self] in
                    guard let self, index < self.nodes.count else { return }
                    self.nodes[index].healthy = status.healthy
                    self.nodes[index].models = status.models
                    self.nodes[index].isLocal = url.contains("localhost") || url.contains("127.0.0.1")
                    self.nodes[index].rpcAvailable = rpcAvailable
                    self.nodes[index].paired = status.paired
                    if !status.nodeID.isEmpty { self.nodes[index].nodeID = status.nodeID }
                    if status.memoryGB > 0 { self.nodes[index].memoryGB = status.memoryGB }
                    if !status.hostname.isEmpty { self.nodes[index].name = status.hostname }
                    // Sync to DiscoveredNodeStore for API exposure
                    self.syncToStore()
                }
            }
        }
    }

    private func syncToStore() {
        let snapshot: [[String: Any]] = nodes.filter { !$0.isLocal }.map { node in
            var dict: [String: Any] = [
                "name": node.name,
                "url": node.url,
                "healthy": node.healthy,
                "memoryGB": node.memoryGB,
                "tier": node.tier.rawValue,
                "tierIcon": node.tier.icon,
                "paired": node.paired,
                "rpcAvailable": node.rpcAvailable,
            ]
            dict["models"] = node.models.map { slot in
                ["name": slot.name, "label": slot.label, "model": slot.model,
                 "port": slot.port, "runtime": slot.runtime, "running": slot.running] as [String: Any]
            }
            return dict
        }
        Task { await DiscoveredNodeStore.shared.update(snapshot) }
    }

    // MARK: - Helpers

    func hostLabel(_ url: String) -> String {
        guard let u = URL(string: url) else { return url }
        let host = u.host ?? url
        if host == "localhost" || host == "127.0.0.1" { return "This Mac" }
        if host.contains(".local") { return host.replacingOccurrences(of: ".local", with: "") }
        return host
    }
}

// MARK: - Bonjour Resolver (NetService-based)

private class BonjourResolver: NSObject, NetServiceDelegate {
    let serviceName: String
    let completion: @MainActor (String?) -> Void
    private var service: NetService?

    init(name: String, completion: @escaping @MainActor (String?) -> Void) {
        self.serviceName = name
        self.completion = completion
        super.init()
    }

    func start() {
        service = NetService(domain: "local.", type: "_nou._tcp.", name: serviceName)
        service?.delegate = self
        service?.schedule(in: .main, forMode: .common)
        service?.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let hostname = sender.hostName ?? "\(serviceName).local"
        let cleanHost = hostname.hasSuffix(".") ? String(hostname.dropLast()) : hostname
        Task { @MainActor in completion(cleanHost) }
        sender.stop()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // Fallback: guess .local hostname from service name
        let guess = serviceName
            .replacingOccurrences(of: "の", with: "no")
            .replacingOccurrences(of: " ", with: "-")
            + ".local"
        Task { @MainActor in completion(guess) }
        sender.stop()
    }
}
