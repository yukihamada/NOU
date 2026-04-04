import Foundation
import Hummingbird

struct RuntimeHandler {
    /// POST /api/runtime  { "slot": "main", "runtime": "llamacpp" } — Requires auth.
    static func handleSwitch(_ request: Request, _ context: some RequestContext) async throws -> Response {
        guard AuthCheck.isAuthorized(request: request) else {
            return Response(status: .unauthorized, headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"Not authorized"}"#)))
        }
        let buf = try await request.body.collect(upTo: 4096)
        guard let data = buf.getData(at: 0, length: buf.readableBytes),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let slot = body["slot"] as? String,
              let runtimeStr = body["runtime"] as? String,
              let runtime = BackendConfig.Runtime(rawValue: runtimeStr) else {
            let err = try JSONSerialization.data(withJSONObject: ["error": "Need slot and runtime (mlx|llamacpp)"])
            return Response(status: .badRequest,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: err)))
        }
        ModelRegistry.setActiveRuntime(slot: slot, runtime: runtime)
        let result: [String: Any] = [
            "slot": slot,
            "runtime": runtime.rawValue,
            "port": ModelRegistry.backends[slot]?.port ?? 0,
            "label": ModelRegistry.backends[slot]?.label ?? ""
        ]
        let out = try JSONSerialization.data(withJSONObject: result)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out)))
    }

    /// POST /api/benchmark  { "slot": "main" }
    /// Runs MLX vs llama.cpp benchmark and auto-selects winner.
    static func handleBenchmark(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let buf = try await request.body.collect(upTo: 4096)
        let body = (try? JSONSerialization.jsonObject(with: buf.getData(at: 0, length: buf.readableBytes) ?? Data())) as? [String: Any]
        let slot = body?["slot"] as? String ?? "main"

        let mlxPort: Int
        let lcppPort: Int
        switch slot {
        case "fast":
            mlxPort = ModelRegistry.portFast
            lcppPort = ModelRegistry.llamacppPortFast
        default:
            mlxPort = ModelRegistry.portMain
            lcppPort = ModelRegistry.llamacppPortMain
        }

        // Run benchmark
        let mlx = await RuntimeBenchmark.bench(port: mlxPort, runtime: .mlx)
        let lcpp = await RuntimeBenchmark.bench(port: lcppPort, runtime: .llamacpp)

        let winner: BackendConfig.Runtime
        if mlx.ok && lcpp.ok {
            winner = lcpp.genTps > mlx.genTps ? .llamacpp : .mlx
        } else if lcpp.ok {
            winner = .llamacpp
        } else {
            winner = .mlx
        }

        // Apply winner
        ModelRegistry.setActiveRuntime(slot: slot, runtime: winner)

        let result: [String: Any] = [
            "slot": slot,
            "winner": winner.rawValue,
            "mlx": [
                "ok": mlx.ok,
                "gen_tps": round(mlx.genTps * 10) / 10,
                "prompt_tps": round(mlx.promptTps * 10) / 10
            ] as [String: Any],
            "llamacpp": [
                "ok": lcpp.ok,
                "gen_tps": round(lcpp.genTps * 10) / 10,
                "prompt_tps": round(lcpp.promptTps * 10) / 10
            ] as [String: Any]
        ]
        let out = try JSONSerialization.data(withJSONObject: result)
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out)))
    }
}
