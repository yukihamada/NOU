import Foundation
import Hummingbird

actor ProxyServer {
    func start() async {
        // Migrate relay secret from UserDefaults to Keychain (one-time, v2.1→v2.2)
        let legacyKey = "nou.relay.secret"
        if let oldSecret = UserDefaults.standard.string(forKey: legacyKey), !oldSecret.isEmpty {
            if KeychainHelper.get(key: "secret") == nil {
                KeychainHelper.set(key: "secret", value: oldSecret)
            }
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }

        let router = Router(context: NOURequestContext.self)
        router.add(middleware: RemoteIPMiddleware())
        // Health
        router.get("/health", use: HealthHandler.handle)
        // Anthropic API
        router.post("/v1/messages/count_tokens", use: ProxyHandler.handleCountTokens)
        router.post("/v1/messages", use: ProxyHandler.handleMessages)
        // OpenAI compatible
        router.post("/v1/chat/completions", use: ProxyHandler.handleChatCompletions)
        router.get("/v1/models", use: ProxyHandler.handleModels)
        // PAC (Proxy Auto-Config)
        router.get("/proxy.pac", use: PACHandler.handle)
        // Dashboard
        router.get("/", use: DashboardHandler.handleRoot)
        router.get("/api/models", use: ModelsHandler.handleList)
        router.get("/api/logs", use: ModelsHandler.handleLogs)
        router.get("/api/stats", use: StatsHandler.handle)
        router.get("/api/nodes", use: NodesHandler.handle)
        // Runtime switch API
        router.post("/api/runtime", use: RuntimeHandler.handleSwitch)
        router.post("/api/benchmark", use: RuntimeHandler.handleBenchmark)
        // P2P model transfer
        router.get("/api/models/available", use: ModelTransferHandler.handleAvailable)
        router.get("/api/models/download/{filename}", use: ModelTransferHandler.handleDownload)
        router.get("/api/models/download-mlx/{name}", use: ModelTransferHandler.handleDownloadMLX)
        // Distributed inference (RPC) API
        router.get("/api/rpc/status", use: RPCHandler.handleStatusV2)
        router.post("/api/rpc/start", use: RPCHandler.handleStartRPC)
        router.post("/api/rpc/stop", use: RPCHandler.handleStopRPC)
        router.post("/api/rpc/workers", use: RPCHandler.handleAddWorker)
        router.delete("/api/rpc/workers", use: RPCHandler.handleRemoveWorker)
        router.post("/api/rpc/refresh", use: RPCHandler.handleRefresh)
        router.post("/api/rpc/enable", use: RPCHandler.handleEnable)
        router.post("/api/rpc/speculative", use: RPCHandler.handleSpeculative)
        // Tunnel status API (legacy)
        router.get("/api/tunnel/status", use: TunnelStatusHandler.handle)
        // Relay status API
        router.get("/api/relay/status", use: RelayStatusHandler.handle)
        router.post("/api/relay/connect", use: RelayStatusHandler.handleConnect)
        router.post("/api/relay/disconnect", use: RelayStatusHandler.handleDisconnect)
        router.post("/api/relay/auto-connect", use: RelayStatusHandler.handleAutoConnect)
        // Plugin API
        router.get("/api/plugins", use: PluginHandler.handleList)
        router.post("/api/plugins/{name}/toggle", use: PluginHandler.handleToggle)
        // Pairing API (public — no auth required for pairing flow)
        router.get("/api/pair/info", use: PairingHandler.handleInfo)
        router.post("/api/pair/request", use: PairingHandler.handleRequest)
        router.post("/api/pair/confirm", use: PairingHandler.handleConfirm)
        router.delete("/api/pair/{nodeID}", use: PairingHandler.handleUnpair)
        // Metrics (VRAM / memory / CPU)
        router.get("/api/metrics", use: MetricsHandler.handle)
        // Rewards (DePIN compute units / NCH)
        router.get("/api/rewards", use: RewardHandler.handle)
        router.post("/api/rewards/wallet", use: RewardHandler.handleSetWallet)
        router.post("/api/rewards/mode", use: RewardHandler.handleSetMode)
        // Blackboard (agent knowledge sharing)
        router.get("/api/blackboard", use: BlackboardHandler.handleList)
        router.get("/api/blackboard/export", use: BlackboardHandler.handleExport)
        router.post("/api/blackboard/sync", use: BlackboardHandler.handleSync)
        router.get("/api/blackboard/{key}", use: BlackboardHandler.handleGet)
        router.post("/api/blackboard/{key}", use: BlackboardHandler.handleSet)
        router.delete("/api/blackboard/{key}", use: BlackboardHandler.handleDelete)

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: ModelRegistry.proxyPort))
        )
        print("[Proxy] Starting on :\(ModelRegistry.proxyPort)")
        try? await app.run()
    }
}
