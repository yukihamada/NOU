import Foundation

// MARK: - Distributed Inference via llama.cpp RPC

/// Manages distributed inference using llama.cpp's RPC backend.
/// An RPC worker exposes a machine's GPU/CPU over the network so a coordinator
/// (llama-server with --rpc) can offload tensor computation to it.
actor DistributedInference {

    static let shared = DistributedInference()

    // MARK: - RPC Worker (this node acts as a worker)

    struct RPCWorker: Codable, Sendable {
        let host: String       // e.g. "192.168.0.5"
        let port: Int          // e.g. 50052
        var status: Status

        enum Status: String, Codable, Sendable {
            case online
            case offline
            case unknown
        }

        var endpoint: String { "\(host):\(port)" }
    }

    private(set) var localRPCProcess: Process?
    private(set) var localRPCPort: Int = 50052
    private(set) var isLocalRPCRunning: Bool = false

    /// Remote RPC workers discovered or manually added
    private(set) var workers: [RPCWorker] = []

    /// Whether distributed mode is enabled (llama-server uses --rpc)
    var distributedEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "nou.distributed.enabled") }
    }

    // MARK: - Paths

    /// Path to the locally built rpc-server binary (built from source with RPC support)
    private var rpcServerBinary: String? {
        let candidates = [
            "\(NSHomeDirectory())/llama.cpp/build/bin/rpc-server",
            "/opt/homebrew/bin/llama-rpc-server",
            "/usr/local/bin/llama-rpc-server",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Path to the locally built llama-server with RPC support
    var llamaServerWithRPC: String? {
        let candidates = [
            "\(NSHomeDirectory())/llama.cpp/build/bin/llama-server",
            "/opt/homebrew/bin/llama-server",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Local RPC Worker

    /// Start the RPC worker on this machine, exposing GPU over the network.
    func startLocalRPC(port: Int = 50052) -> (ok: Bool, message: String) {
        guard !isLocalRPCRunning else {
            return (true, "RPC worker already running on port \(localRPCPort)")
        }
        guard let binary = rpcServerBinary else {
            return (false, "rpc-server binary not found. Build llama.cpp from source with -DGGML_RPC=ON")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--host", "0.0.0.0", "--port", "\(port)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            localRPCProcess = process
            localRPCPort = port
            isLocalRPCRunning = true
            print("[DistributedInference] Started local RPC worker on port \(port), PID: \(process.processIdentifier)")
            return (true, "RPC worker started on port \(port)")
        } catch {
            return (false, "Failed to start RPC worker: \(error.localizedDescription)")
        }
    }

    /// Stop the local RPC worker.
    func stopLocalRPC() -> String {
        guard let process = localRPCProcess, process.isRunning else {
            isLocalRPCRunning = false
            localRPCProcess = nil
            return "RPC worker not running"
        }
        process.terminate()
        localRPCProcess = nil
        isLocalRPCRunning = false
        print("[DistributedInference] Stopped local RPC worker")
        return "RPC worker stopped"
    }

    // MARK: - Remote RPC Workers

    /// Add a remote RPC worker endpoint.
    func addWorker(host: String, port: Int = 50052) {
        let worker = RPCWorker(host: host, port: port, status: .unknown)
        if !workers.contains(where: { $0.host == host && $0.port == port }) {
            workers.append(worker)
            saveWorkers()
        }
    }

    /// Remove a remote RPC worker.
    func removeWorker(host: String, port: Int) {
        workers.removeAll { $0.host == host && $0.port == port }
        saveWorkers()
    }

    /// Probe a single RPC worker to check if it is online.
    /// RPC server uses a raw TCP protocol, so we just check if the port is open.
    func probeWorker(host: String, port: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "rpc-probe")
            let socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, nil, nil)
            guard socket != nil else {
                continuation.resume(returning: false)
                return
            }

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(port).bigEndian
            addr.sin_addr.s_addr = inet_addr(host)

            let addrData = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<sockaddr_in>.size) {
                    Data(bytes: $0, count: MemoryLayout<sockaddr_in>.size)
                }
            } as CFData

            queue.async {
                let result = CFSocketConnectToAddress(socket, addrData, 2.0) // 2s timeout
                CFSocketInvalidate(socket)
                continuation.resume(returning: result == .success)
            }
        }
    }

    /// Refresh status of all known workers.
    func refreshWorkers() async {
        for i in workers.indices {
            let w = workers[i]
            let online = await probeWorker(host: w.host, port: w.port)
            workers[i] = RPCWorker(host: w.host, port: w.port, status: online ? .online : .offline)
        }
    }

    /// Get all online workers as a comma-separated --rpc argument.
    /// e.g. "192.168.0.5:50052,192.168.0.10:50052"
    func rpcArgument() -> String? {
        let online = workers.filter { $0.status == .online }
        guard !online.isEmpty else { return nil }
        return online.map { $0.endpoint }.joined(separator: ",")
    }

    // MARK: - Distributed llama-server

    /// Build the command to start llama-server with RPC offloading.
    /// The coordinator runs on this Mac, offloading layers to RPC workers.
    /// Pass draftModelPath to enable speculative decoding (smaller draft model).
    func buildLlamaServerCommand(
        modelPath: String,
        port: Int = 5030,
        ctxSize: Int = 4096,
        nGpuLayers: Int = 99,
        draftModelPath: String? = nil
    ) async -> (command: String, args: [String])? {
        guard let binary = llamaServerWithRPC else { return nil }

        await refreshWorkers()
        guard let rpc = rpcArgument() else { return nil }

        var args = [
            "--model", modelPath,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--rpc", rpc,
            "--n-gpu-layers", "\(nGpuLayers)",
            "--ctx-size", "\(ctxSize)",
        ]

        // Speculative decoding: run a small draft model alongside the main model
        // Draft model generates candidate tokens, main model verifies in parallel
        if let draft = draftModelPath ?? speculativeDraftModel {
            args += ["--draft-model", draft, "--draft-max-tokens", "8"]
        }

        return (binary, args)
    }

    // MARK: - Speculative Decoding

    var speculativeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "nou.speculative.enabled")
    }

    var speculativeDraftModel: String? {
        UserDefaults.standard.string(forKey: "nou.speculative.draftModel")
    }

    func setSpeculative(enabled: Bool, draftModelPath: String? = nil) {
        UserDefaults.standard.set(enabled, forKey: "nou.speculative.enabled")
        if let path = draftModelPath {
            UserDefaults.standard.set(path, forKey: "nou.speculative.draftModel")
        }
    }

    // MARK: - Auto-sync RPC workers from discovered nodes

    /// Called by NOUBrowser when nodes are discovered.
    /// Automatically adds paired+RPC-capable remote nodes as RPC workers.
    func syncWorkersFromNodes(_ nodes: [NOUNode]) async {
        guard distributedEnabled else { return }
        for node in nodes where !node.isLocal && node.healthy && node.rpcAvailable {
            // Extract IP from node URL (e.g. "http://192.168.0.5:4001" → "192.168.0.5")
            guard let url = URL(string: node.url), let host = url.host else { continue }
            // Skip if already tracked
            if workers.contains(where: { $0.host == host }) { continue }
            print("[DistributedInference] Auto-adding RPC worker: \(host):50052 (\(node.name))")
            addWorker(host: host, port: 50052)
        }
    }

    // MARK: - Enable/Disable

    func setDistributedEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "nou.distributed.enabled")
    }

    // MARK: - Persistence

    private func saveWorkers() {
        let endpoints = workers.map { "\($0.host):\($0.port)" }
        UserDefaults.standard.set(endpoints, forKey: "nou.distributed.workers")
    }

    func loadWorkers() {
        let endpoints = UserDefaults.standard.stringArray(forKey: "nou.distributed.workers") ?? []
        workers = endpoints.compactMap { ep -> RPCWorker? in
            let parts = ep.split(separator: ":")
            guard parts.count == 2, let port = Int(parts[1]) else { return nil }
            return RPCWorker(host: String(parts[0]), port: port, status: .unknown)
        }
    }

    // MARK: - Status

    struct Status: Codable {
        let localRPCRunning: Bool
        let localRPCPort: Int
        let distributedEnabled: Bool
        let workers: [RPCWorker]
        let rpcServerAvailable: Bool
        let llamaServerRPCAvailable: Bool
    }

    func status() -> Status {
        Status(
            localRPCRunning: isLocalRPCRunning,
            localRPCPort: localRPCPort,
            distributedEnabled: distributedEnabled,
            workers: workers,
            rpcServerAvailable: rpcServerBinary != nil,
            llamaServerRPCAvailable: llamaServerWithRPC != nil
        )
    }
}
