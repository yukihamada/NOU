import Foundation

struct BackendConfig {
    let name: String
    let mlxModel: String
    let port: Int
    let label: String
    let runtime: Runtime  // MLX or llama.cpp

    enum Runtime: String, Codable {
        case mlx = "mlx"
        case llamacpp = "llamacpp"
    }
}

struct ModelPreset {
    let id: String
    let displayName: String
    let mlxModelID: String
    let ramGB: Int
    let slot: String  // "main" | "fast" | "vision"
}

enum ModelRegistry {

    // MARK: - Preset Catalog

    static let presets: [ModelPreset] = [
        // ─── Main slot (高品質・コーディング) ───
        // Qwen3 (Alibaba, 2025)
        ModelPreset(id: "qwen3-235b", displayName: "Qwen3-235B-A22B MoE ★",  mlxModelID: "mlx-community/Qwen3-235B-A22B-4bit",           ramGB: 130, slot: "main"),
        ModelPreset(id: "qwen3-32b",  displayName: "Qwen3-32B",               mlxModelID: "mlx-community/Qwen3-32B-4bit",                 ramGB: 20,  slot: "main"),
        ModelPreset(id: "qwen3-14b",  displayName: "Qwen3-14B",               mlxModelID: "mlx-community/Qwen3-14B-4bit",                 ramGB: 9,   slot: "main"),
        // Gemma 4 (Google, 2025)
        ModelPreset(id: "gemma4-31b", displayName: "Gemma 4 31B",             mlxModelID: "mlx-community/gemma-4-31b-it-4bit",            ramGB: 20,  slot: "main"),
        // Gemma 3 (Google, 2025)
        ModelPreset(id: "gemma3-27b", displayName: "Gemma 3 27B",             mlxModelID: "mlx-community/gemma-3-27b-it-4bit",            ramGB: 18,  slot: "main"),
        // DeepSeek-R1 distilled (DeepSeek, 2025) — reasoning specialist
        ModelPreset(id: "ds-r1-32b",  displayName: "DeepSeek-R1 32B (推論)",  mlxModelID: "mlx-community/DeepSeek-R1-Distill-Qwen-32B-4bit", ramGB: 20, slot: "main"),
        ModelPreset(id: "ds-r1-14b",  displayName: "DeepSeek-R1 14B (推論)",  mlxModelID: "mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit", ramGB: 9,  slot: "main"),
        // Llama 4 Scout (Meta, 2025) — MoE, efficient
        ModelPreset(id: "llama4-s",   displayName: "Llama 4 Scout 17B MoE",   mlxModelID: "mlx-community/Llama-4-Scout-17B-16E-Instruct-4bit", ramGB: 12, slot: "main"),
        // Mistral (2025)
        ModelPreset(id: "mistral-24b", displayName: "Mistral Small 3.1 24B",  mlxModelID: "mlx-community/Mistral-Small-3.1-24B-Instruct-2503-4bit", ramGB: 15, slot: "main"),
        // MiniMax-Text-01 (MiniMax, 2025) — 456B MoE, 45.9B active
        ModelPreset(id: "minimax-01", displayName: "MiniMax-Text-01 MoE",     mlxModelID: "mlx-community/MiniMax-Text-01-4bit",           ramGB: 28,  slot: "main"),

        // ─── Fast slot (高速・軽量) ───
        ModelPreset(id: "qwen3-8b",   displayName: "Qwen3-8B (推奨・高速)",   mlxModelID: "mlx-community/Qwen3-8B-4bit",                  ramGB: 5,   slot: "fast"),
        ModelPreset(id: "qwen3-30b-moe", displayName: "Qwen3-30B-A3B MoE",   mlxModelID: "mlx-community/Qwen3-30B-A3B-4bit",             ramGB: 8,   slot: "fast"),
        ModelPreset(id: "gemma4-12b", displayName: "Gemma 4 12B",             mlxModelID: "mlx-community/gemma-4-12b-it-4bit",            ramGB: 8,   slot: "fast"),
        ModelPreset(id: "gemma3-12b", displayName: "Gemma 3 12B",             mlxModelID: "mlx-community/gemma-3-12b-it-4bit",            ramGB: 8,   slot: "fast"),
        ModelPreset(id: "qwen3-4b",   displayName: "Qwen3-4B (超軽量)",       mlxModelID: "mlx-community/Qwen3-4B-4bit",                  ramGB: 3,   slot: "fast"),
        ModelPreset(id: "gemma3-4b",  displayName: "Gemma 3 4B (超軽量)",     mlxModelID: "mlx-community/gemma-3-4b-it-4bit",             ramGB: 3,   slot: "fast"),
        ModelPreset(id: "ds-r1-7b",   displayName: "DeepSeek-R1 7B (推論)",   mlxModelID: "mlx-community/DeepSeek-R1-Distill-Qwen-7B-4bit", ramGB: 5,  slot: "fast"),

        // ─── Vision slot ───
        ModelPreset(id: "gemma4-4b-vl", displayName: "Gemma 4 4B Vision",    mlxModelID: "mlx-community/gemma-4-4b-it-4bit",             ramGB: 3,   slot: "vision"),
        ModelPreset(id: "qwen3-vl-8b",  displayName: "Qwen3-VL-8B Vision",   mlxModelID: "mlx-community/Qwen3-VL-8B-Instruct-4bit",      ramGB: 5,   slot: "vision"),
        ModelPreset(id: "qwen3-vl-4b",  displayName: "Qwen3-VL-4B Vision",   mlxModelID: "mlx-community/Qwen3-VL-4B-Instruct-4bit",      ramGB: 3,   slot: "vision"),
    ]

    // MARK: - Active Model Selection (UserDefaults)

    static func activeModelID(slot: String) -> String {
        let defaults = ["main": "qwen3-32b", "fast": "qwen3-8b", "vision": "qwen3-vl-8b"]
        return UserDefaults.standard.string(forKey: "nou.model.\(slot)") ?? defaults[slot] ?? "qwen122b"
    }

    static func setActiveModel(slot: String, presetID: String) {
        UserDefaults.standard.set(presetID, forKey: "nou.model.\(slot)")
        updateEnvFile()
    }

    static func activePreset(slot: String) -> ModelPreset {
        let id = activeModelID(slot: slot)
        return presets.first(where: { $0.id == id && $0.slot == slot })
            ?? presets.first(where: { $0.slot == slot })!
    }

    // MARK: - Runtime Selection (UserDefaults)

    static func activeRuntime(slot: String) -> BackendConfig.Runtime {
        let raw = UserDefaults.standard.string(forKey: "nou.runtime.\(slot)") ?? "mlx"
        return BackendConfig.Runtime(rawValue: raw) ?? .mlx
    }

    static func setActiveRuntime(slot: String, runtime: BackendConfig.Runtime) {
        UserDefaults.standard.set(runtime.rawValue, forKey: "nou.runtime.\(slot)")
    }

    /// ~/.nou_env に環境変数を書き出す（ai.sh が source して使う）
    private static func updateEnvFile() {
        let main   = activePreset(slot: "main").mlxModelID
        let fast   = activePreset(slot: "fast").mlxModelID
        let vision = activePreset(slot: "vision").mlxModelID
        let content = """
        export MLX_MODEL_MAIN="\(main)"
        export MLX_MODEL_FAST="\(fast)"
        export MLX_MODEL_VISION="\(vision)"
        """
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nou_env")
        try? content.write(to: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Dynamic Backends

    static func port(for slot: String) -> Int {
        let rt = activeRuntime(slot: slot)
        switch (slot, rt) {
        case ("main", .llamacpp):  return llamacppPortMain
        case ("fast", .llamacpp):  return llamacppPortFast
        case ("main", .mlx):      return portMain
        case ("fast", .mlx):      return portFast
        case ("vision", _):       return portVision
        default:                   return portMain
        }
    }

    static var backends: [String: BackendConfig] {
        let mainPreset   = activePreset(slot: "main")
        let fastPreset   = activePreset(slot: "fast")
        let visionPreset = activePreset(slot: "vision")
        return [
            "main":   BackendConfig(name: "main",   mlxModel: mainPreset.mlxModelID,   port: port(for: "main"),   label: mainPreset.displayName, runtime: activeRuntime(slot: "main")),
            "fast":   BackendConfig(name: "fast",   mlxModel: fastPreset.mlxModelID,   port: port(for: "fast"),   label: fastPreset.displayName,  runtime: activeRuntime(slot: "fast")),
            "vision": BackendConfig(name: "vision", mlxModel: visionPreset.mlxModelID, port: port(for: "vision"), label: visionPreset.displayName, runtime: activeRuntime(slot: "vision")),
        ]
    }

    static let portMain   = Int(ProcessInfo.processInfo.environment["MLX_PORT_MAIN"]   ?? "5000") ?? 5000
    static let portFast   = Int(ProcessInfo.processInfo.environment["MLX_PORT_FAST"]   ?? "5001") ?? 5001
    static let portVision = Int(ProcessInfo.processInfo.environment["MLX_PORT_VISION"] ?? "5002") ?? 5002
    static let proxyPort  = Int(ProcessInfo.processInfo.environment["PROXY_PORT"]      ?? "4001") ?? 4001

    // llama.cpp backend ports (used when runtime == .llamacpp)
    static let llamacppPortMain   = Int(ProcessInfo.processInfo.environment["LLAMACPP_PORT_MAIN"]   ?? "5020") ?? 5020
    static let llamacppPortFast   = Int(ProcessInfo.processInfo.environment["LLAMACPP_PORT_FAST"]   ?? "5021") ?? 5021

    // MARK: - Routing

    static let anthropicRoutes: [String: String] = [
        "claude-sonnet-4-6": "main",
        "claude-sonnet-4-6-20250514": "main",
        "claude-opus-4-6": "main",
        "claude-opus-4-6-20250514": "main",
        "claude-3-5-sonnet-20241022": "main",
        "claude-3-5-sonnet-latest": "main",
        "claude-haiku-4-5-20251001": "fast",
        "claude-3-5-haiku-latest": "fast",
        "deepseek-chat": "main",
        "deepseek-v4": "main",
    ]

    static let openaiPrefixes: [(String, String)] = [
        ("nou-agent", "main"),  // Agent mode with tool-use loop
        ("agent", "main"),
        ("nou", "main"),
        ("auto", "main"),
        ("smart", "main"),
        // Qwen3
        ("qwen3-235b", "main"), ("qwen3-32b", "main"), ("qwen3-14b", "main"),
        ("qwen3-30b", "fast"),  ("qwen3-8b", "fast"),  ("qwen3-4b", "fast"),
        ("qwen3-vl-8b", "vision"), ("qwen3-vl-4b", "vision"),
        // Gemma
        ("gemma-4-31b", "main"), ("gemma-4-12b", "fast"), ("gemma-4-4b", "vision"),
        ("gemma-3-27b", "main"), ("gemma-3-12b", "fast"), ("gemma-3-4b", "fast"),
        ("gemma4", "main"), ("gemma3", "main"),
        // DeepSeek
        ("deepseek-r1-32b", "main"), ("deepseek-r1-14b", "main"), ("deepseek-r1-7b", "fast"),
        ("deepseek-r1", "main"), ("deepseek", "main"),
        // Llama 4
        ("llama-4-scout", "main"), ("llama4", "main"),
        // Mistral
        ("mistral-small", "main"), ("mistral", "main"),
        // MiniMax
        ("minimax", "main"),
        // OpenAI compat aliases
        ("gpt-4o-mini", "fast"), ("gpt-4", "main"), ("gpt-3.5", "fast"),
    ]

    static func backend(for anthropicModel: String, hasImages: Bool = false) -> BackendConfig {
        if hasImages { return backends["vision"] ?? backends["main"]! }
        let key = anthropicRoutes[anthropicModel] ?? "main"
        return backends[key] ?? backends["main"]!
    }

    static func backendOpenAI(for model: String, hasImages: Bool = false) -> BackendConfig {
        if hasImages { return backends["vision"] ?? backends["main"]! }
        let lower = model.lowercased().replacingOccurrences(of: "openai/", with: "")
        for (prefix, key) in openaiPrefixes {
            if lower.hasPrefix(prefix) { return backends[key] ?? backends["main"]! }
        }
        return backend(for: model, hasImages: hasImages)
    }
}
