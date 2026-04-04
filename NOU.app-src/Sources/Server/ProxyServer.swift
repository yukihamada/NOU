import Foundation
import Hummingbird

actor ProxyServer {
    func start() async {
        let router = Router()
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
        router.get("/api/rpc/status", use: RPCHandler.handleStatus)
        router.post("/api/rpc/start", use: RPCHandler.handleStartRPC)
        router.post("/api/rpc/stop", use: RPCHandler.handleStopRPC)
        router.post("/api/rpc/workers", use: RPCHandler.handleAddWorker)
        router.delete("/api/rpc/workers", use: RPCHandler.handleRemoveWorker)
        router.post("/api/rpc/refresh", use: RPCHandler.handleRefresh)
        router.post("/api/rpc/enable", use: RPCHandler.handleEnable)
        // Tunnel status API
        router.get("/api/tunnel/status", use: TunnelStatusHandler.handle)
        // Plugin API
        router.get("/api/plugins", use: PluginHandler.handleList)
        router.post("/api/plugins/{name}/toggle", use: PluginHandler.handleToggle)
        // Pairing API (public — no auth required for pairing flow)
        router.get("/api/pair/info", use: PairingHandler.handleInfo)
        router.post("/api/pair/request", use: PairingHandler.handleRequest)
        router.post("/api/pair/confirm", use: PairingHandler.handleConfirm)
        router.delete("/api/pair/{nodeID}", use: PairingHandler.handleUnpair)

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: ModelRegistry.proxyPort))
        )
        print("[Proxy] Starting on :\(ModelRegistry.proxyPort)")
        try? await app.run()
    }
}
