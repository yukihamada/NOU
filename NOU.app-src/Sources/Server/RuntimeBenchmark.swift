import Foundation

// MARK: - Runtime Benchmark
// On first launch, benchmarks MLX vs llama.cpp and picks the faster default.

enum RuntimeBenchmark {

    struct Result {
        let runtime: BackendConfig.Runtime
        let port: Int
        let promptTps: Double   // input tokens/sec
        let genTps: Double      // output tokens/sec
        let ok: Bool
    }

    /// Run benchmark for a single backend port. Returns nil if unreachable.
    static func bench(port: Int, runtime: BackendConfig.Runtime) async -> Result {
        let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!
        let body: [String: Any] = [
            "model": "bench",
            "messages": [["role": "user", "content": "Write a short haiku about the ocean."]],
            "max_tokens": 40,
            "stream": false
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return Result(runtime: runtime, port: port, promptTps: 0, genTps: 0, ok: false)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = jsonData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Result(runtime: runtime, port: port, promptTps: 0, genTps: 0, ok: false)
            }

            // MLX returns: usage.prompt_tps, usage.generation_tps
            // llama.cpp returns: timings.prompt_per_second, timings.predicted_per_second
            var promptTps: Double = 0
            var genTps: Double = 0

            if let usage = json["usage"] as? [String: Any] {
                promptTps = usage["prompt_tps"] as? Double ?? 0
                genTps = usage["generation_tps"] as? Double ?? 0
            }
            if let timings = json["timings"] as? [String: Any] {
                let pt = timings["prompt_per_second"] as? Double ?? 0
                let gt = timings["predicted_per_second"] as? Double ?? 0
                if pt > promptTps { promptTps = pt }
                if gt > genTps { genTps = gt }
            }

            return Result(runtime: runtime, port: port, promptTps: promptTps, genTps: genTps, ok: true)
        } catch {
            return Result(runtime: runtime, port: port, promptTps: 0, genTps: 0, ok: false)
        }
    }

    /// Benchmark all available backends for a slot and pick the fastest.
    /// Returns (winner runtime, results summary string).
    static func benchSlot(mlxPort: Int, llamacppPort: Int) async -> (BackendConfig.Runtime, String) {
        // Run both in parallel
        async let mlxResult = bench(port: mlxPort, runtime: .mlx)
        async let lcppResult = bench(port: llamacppPort, runtime: .llamacpp)

        let mlx = await mlxResult
        let lcpp = await lcppResult

        var lines: [String] = []
        if mlx.ok {
            lines.append("  MLX:       \(String(format: "%.0f", mlx.genTps)) tok/s gen, \(String(format: "%.0f", mlx.promptTps)) tok/s prompt")
        } else {
            lines.append("  MLX:       not available")
        }
        if lcpp.ok {
            lines.append("  llama.cpp: \(String(format: "%.0f", lcpp.genTps)) tok/s gen, \(String(format: "%.0f", lcpp.promptTps)) tok/s prompt")
        } else {
            lines.append("  llama.cpp: not available")
        }

        // Pick winner by generation speed (most important for UX)
        let winner: BackendConfig.Runtime
        if mlx.ok && lcpp.ok {
            winner = lcpp.genTps > mlx.genTps ? .llamacpp : .mlx
        } else if lcpp.ok {
            winner = .llamacpp
        } else {
            winner = .mlx
        }
        lines.append("  Winner:    \(winner.rawValue)")

        return (winner, lines.joined(separator: "\n"))
    }

    /// Key to track whether benchmark has been run
    static let benchDoneKey = "nou.benchmark.done"

    /// Run first-launch benchmark for main slot if not done yet.
    /// Call from MenubarController after backends have had time to start.
    static func runIfNeeded(mlxPort: Int, llamacppPort: Int, slot: String = "main") async {
        guard !UserDefaults.standard.bool(forKey: benchDoneKey) else { return }

        print("[Benchmark] Starting first-launch benchmark for slot=\(slot)...")

        // Warm up: give backends a moment
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Run warmup request (first request is always slow due to model load)
        _ = await bench(port: mlxPort, runtime: .mlx)
        _ = await bench(port: llamacppPort, runtime: .llamacpp)

        // Wait a bit then run actual benchmark
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let (winner, summary) = await benchSlot(mlxPort: mlxPort, llamacppPort: llamacppPort)

        print("[Benchmark] Results:\n\(summary)")

        ModelRegistry.setActiveRuntime(slot: slot, runtime: winner)
        UserDefaults.standard.set(true, forKey: benchDoneKey)

        print("[Benchmark] Set \(slot) runtime to \(winner.rawValue)")
    }
}
