import Foundation

/// HTTP client for communicating with remote NOU nodes.
enum NOUAPIClient {

    struct NodeStatus {
        var healthy: Bool
        var models: [SlotInfo]
        var memoryGB: Int
        var hostname: String
        var nodeID: String
        var paired: Bool
    }

    /// Check health and fetch models from a NOU node.
    /// Also probes /api/pair/info to get the node's ID and pairing status.
    static func fetchNodeStatus(url: String) async -> NodeStatus {
        let (healthy, memoryGB, hostname) = await healthDetailed(url: url)
        guard healthy else { return NodeStatus(healthy: false, models: [], memoryGB: 0, hostname: "", nodeID: "", paired: false) }
        let models = await models(url: url)
        let pairInfo = await fetchPairInfo(url: url)
        let isPaired = await MainActor.run { PairingManager.shared.isPaired(pairInfo.nodeID) }
        return NodeStatus(
            healthy: true, models: models, memoryGB: memoryGB, hostname: hostname,
            nodeID: pairInfo.nodeID, paired: isPaired
        )
    }

    // MARK: - Auth Header

    /// Add pairing auth header to a request if we have a token for the target node.
    @MainActor
    static func addAuthHeader(to request: inout URLRequest, forNodeURL url: String) {
        // Find the node ID for this URL from the browser
        // Use a simpler approach: look up by checking paired nodes
        let paired = PairingManager.shared.pairedNodes
        for (nodeID, _) in paired {
            if let token = PairingManager.shared.generateToken(forNode: nodeID) {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return
            }
        }
    }

    /// Add auth header for a specific known node ID.
    @MainActor
    static func addAuthHeader(to request: inout URLRequest, forNodeID nodeID: String) {
        if let token = PairingManager.shared.generateToken(forNode: nodeID) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// GET /health — returns (alive, memoryGB, hostname)
    static func healthDetailed(url: String) async -> (Bool, Int, String) {
        guard let requestURL = URL(string: "\(url)/health") else { return (false, 0, "") }
        var req = URLRequest(url: requestURL)
        req.timeoutInterval = 3
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return (false, 0, "") }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let mem = json["memory_gb"] as? Int ?? 0
            let host = json["hostname"] as? String ?? ""
            return (true, mem, host)
        } catch {
            return (false, 0, "")
        }
    }

    /// GET /health — returns true if the node is alive.
    static func health(url: String) async -> Bool {
        guard let requestURL = URL(string: "\(url)/health") else { return false }
        var req = URLRequest(url: requestURL)
        req.timeoutInterval = 3
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// GET /api/models — returns the list of model slots.
    static func models(url: String) async -> [SlotInfo] {
        guard let requestURL = URL(string: "\(url)/api/models") else { return [] }
        var req = URLRequest(url: requestURL)
        req.timeoutInterval = 3
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return arr.map { m in
                SlotInfo(
                    name: m["name"] as? String ?? "",
                    label: m["label"] as? String ?? "",
                    model: m["model"] as? String ?? "",
                    port: m["port"] as? Int ?? 0,
                    runtime: m["runtime"] as? String ?? "mlx",
                    running: m["running"] as? Bool ?? false
                )
            }.sorted { $0.name < $1.name }
        } catch {
            return []
        }
    }

    /// POST /api/runtime — switch runtime for a slot on a remote node.
    static func switchRuntime(url: String, slot: String, runtime: String) async -> Bool {
        guard let requestURL = URL(string: "\(url)/api/runtime") else { return false }
        var req = URLRequest(url: requestURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["slot": slot, "runtime": runtime])
        req.timeoutInterval = 5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - P2P Model Transfer

    struct RemoteModel {
        let name: String
        let size: Int64
        let type: String  // "gguf" or "mlx"
        let nodeURL: String
        let nodeName: String
    }

    /// GET /api/models/available — list models on a remote node.
    static func availableModels(url: String) async -> [RemoteModel] {
        guard let requestURL = URL(string: "\(url)/api/models/available") else { return [] }
        var req = URLRequest(url: requestURL)
        req.timeoutInterval = 5
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            return arr.map { m in
                RemoteModel(
                    name: m["name"] as? String ?? "",
                    size: (m["size"] as? Int64) ?? Int64(m["size"] as? Int ?? 0),
                    type: m["type"] as? String ?? "gguf",
                    nodeURL: url,
                    nodeName: ""
                )
            }
        } catch {
            return []
        }
    }

    /// Download a GGUF model file from a remote node to ~/models/
    static func downloadGGUF(nodeURL: String, filename: String, progress: @escaping (Double) -> Void) async -> Bool {
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        guard let url = URL(string: "\(nodeURL)/api/models/download/\(encoded)") else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let modelsDir = home.appendingPathComponent("models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let destPath = modelsDir.appendingPathComponent(filename)

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 3600  // 1 hour for large models
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: req)
            let expectedLength = (response as? HTTPURLResponse)
                .flatMap { Int64($0.value(forHTTPHeaderField: "Content-Length") ?? "") } ?? 0

            let handle = try FileHandle(forWritingTo: {
                FileManager.default.createFile(atPath: destPath.path, contents: nil)
                return destPath
            }())
            defer { handle.closeFile() }

            var downloaded: Int64 = 0
            var buffer = Data()
            let flushSize = 1024 * 1024  // 1MB
            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= flushSize {
                    handle.write(buffer)
                    downloaded += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expectedLength > 0 {
                        progress(Double(downloaded) / Double(expectedLength))
                    }
                }
            }
            if !buffer.isEmpty {
                handle.write(buffer)
                downloaded += Int64(buffer.count)
            }
            progress(1.0)
            return true
        } catch {
            print("[NOUAPIClient] Download failed: \(error)")
            return false
        }
    }

    /// Download an MLX model from a remote node to HuggingFace cache
    static func downloadMLX(nodeURL: String, modelName: String, progress: @escaping (Double) -> Void) async -> Bool {
        let encoded = modelName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelName
        guard let url = URL(string: "\(nodeURL)/api/models/download-mlx/\(encoded)") else { return false }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let repoName = "models--" + modelName.replacingOccurrences(of: "/", with: "--")
        let hfCache = home.appendingPathComponent(".cache/huggingface/hub")
        let snapshotDir = hfCache.appendingPathComponent(repoName).appendingPathComponent("snapshots")
        let destDir = snapshotDir.appendingPathComponent("p2p-transfer")
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Download tar and extract
        let tarPath = NSTemporaryDirectory() + "\(UUID().uuidString).tar"
        defer { try? FileManager.default.removeItem(atPath: tarPath) }

        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 3600
            let (data, _) = try await URLSession.shared.data(for: req)
            try data.write(to: URL(fileURLWithPath: tarPath))
            progress(0.8)

            // Extract tar
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xf", tarPath, "-C", destDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return false }
            progress(1.0)
            return true
        } catch {
            print("[NOUAPIClient] MLX download failed: \(error)")
            return false
        }
    }

    // MARK: - Pairing

    struct PairInfo {
        let nodeID: String
        let name: String
        let memoryGB: Int
    }

    /// GET /api/pair/info — Fetch remote node's ID and name.
    static func fetchPairInfo(url: String) async -> PairInfo {
        guard let requestURL = URL(string: "\(url)/api/pair/info") else {
            return PairInfo(nodeID: "", name: "", memoryGB: 0)
        }
        var req = URLRequest(url: requestURL)
        req.timeoutInterval = 3
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return PairInfo(nodeID: "", name: "", memoryGB: 0)
            }
            return PairInfo(
                nodeID: json["node_id"] as? String ?? "",
                name: json["name"] as? String ?? "",
                memoryGB: json["memory_gb"] as? Int ?? 0
            )
        } catch {
            return PairInfo(nodeID: "", name: "", memoryGB: 0)
        }
    }

    /// POST /api/pair/request — Send a pairing request to a remote node.
    /// This causes the remote node to show a PIN on screen.
    static func sendPairRequest(url: String) async -> Bool {
        guard let requestURL = URL(string: "\(url)/api/pair/request") else { return false }
        let localNodeID = await MainActor.run { PairingManager.shared.nodeID }
        let hostname = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        var req = URLRequest(url: requestURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "node_id": localNodeID,
            "name": hostname
        ])
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            let status = json["status"] as? String ?? ""
            return status == "pending" || status == "already_paired"
        } catch {
            return false
        }
    }

    /// POST /api/pair/confirm — Confirm pairing with the PIN.
    /// Returns the shared secret on success.
    static func confirmPairing(url: String, pin: String) async -> (success: Bool, secret: String, remoteNodeID: String) {
        guard let requestURL = URL(string: "\(url)/api/pair/confirm") else {
            return (false, "", "")
        }
        let localNodeID = await MainActor.run { PairingManager.shared.nodeID }
        var req = URLRequest(url: requestURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "node_id": localNodeID,
            "pin": pin
        ])
        req.timeoutInterval = 5
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["status"] as? String == "paired",
                  let secret = json["secret"] as? String,
                  let remoteNodeID = json["node_id"] as? String else {
                return (false, "", "")
            }
            return (true, secret, remoteNodeID)
        } catch {
            return (false, "", "")
        }
    }

    // MARK: - Distributed Inference (RPC)

    /// Check if a NOU node has an RPC worker running.
    /// Queries the node's NOU API at /api/rpc/status.
    static func probeRPCWorker(url: String) async -> Bool {
        guard let requestURL = URL(string: "\(url)/api/rpc/status") else { return false }
        var req = URLRequest(url: requestURL)
        req.timeoutInterval = 3
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return json["local_rpc_running"] as? Bool ?? false
        } catch {
            return false
        }
    }

    /// Start the RPC worker on a remote NOU node.
    static func startRemoteRPC(url: String, port: Int = 50052) async -> Bool {
        guard let requestURL = URL(string: "\(url)/api/rpc/start") else { return false }
        var req = URLRequest(url: requestURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["port": port])
        req.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return json["ok"] as? Bool ?? false
        } catch {
            return false
        }
    }

    /// Stop the RPC worker on a remote NOU node.
    static func stopRemoteRPC(url: String) async -> Bool {
        guard let requestURL = URL(string: "\(url)/api/rpc/stop") else { return false }
        var req = URLRequest(url: requestURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    struct BenchmarkResult {
        let slot: String
        let winner: String
        let mlxGenTps: Double
        let mlxOk: Bool
        let llamacppGenTps: Double
        let llamacppOk: Bool
    }

    /// POST /api/benchmark — run benchmark on a remote node.
    static func benchmark(url: String, slot: String) async -> BenchmarkResult? {
        guard let requestURL = URL(string: "\(url)/api/benchmark") else { return nil }
        var req = URLRequest(url: requestURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["slot": slot])
        req.timeoutInterval = 60
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let winner = json["winner"] as? String else { return nil }
            let mlx = json["mlx"] as? [String: Any] ?? [:]
            let lcpp = json["llamacpp"] as? [String: Any] ?? [:]
            return BenchmarkResult(
                slot: slot,
                winner: winner,
                mlxGenTps: mlx["gen_tps"] as? Double ?? 0,
                mlxOk: mlx["ok"] as? Bool ?? false,
                llamacppGenTps: lcpp["gen_tps"] as? Double ?? 0,
                llamacppOk: lcpp["ok"] as? Bool ?? false
            )
        } catch {
            return nil
        }
    }
}
