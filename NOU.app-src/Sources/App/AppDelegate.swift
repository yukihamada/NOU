import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var menubarController: MenubarController?
    var proxyServer: ProxyServer?
    var publisher: NOUPublisher?
    var browser: NOUBrowser?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Migrate default models to Gemma 4 (one-time)
        ModelRegistry.migrateToGemma4Defaults()
        // Fetch remote model catalog from nou.run (async, non-blocking)
        Task { await ModelCatalogFetcher.shared.loadIfNeeded() }
        // 多重起動防止 — 同じ Bundle ID の別プロセスがあれば前面に出してこちらは終了
        let bundleID = Bundle.main.bundleIdentifier ?? "com.enablerdao.nou"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: .activateAllWindows)
            NSApp.terminate(nil)
            return
        }

        // Register as login item (auto-start on login)
        registerLoginItem()
        // Start Bonjour advertisement (delay to ensure RunLoop is active)
        publisher = NOUPublisher()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.publisher?.start()
        }

        // Start network browser for discovering other NOU nodes
        let nodeBrowser = NOUBrowser()
        browser = nodeBrowser
        Task { @MainActor in
            nodeBrowser.start()
        }

        // Create unified menu bar controller with browser
        menubarController = MenubarController(browser: nodeBrowser)

        // Register browser with FallbackRouter for Tier2 (own devices)
        FallbackRouter.browserRef = nodeBrowser

        // Initialize distributed inference: load saved RPC workers
        Task {
            await DistributedInference.shared.loadWorkers()
            await DistributedInference.shared.refreshWorkers()
        }

        // Start HTTP server (always — serves health endpoint even in relay mode)
        proxyServer = ProxyServer()
        Task {
            await proxyServer?.start()
        }

        // Auto-start tunnel if previously enabled
        Task { @MainActor in
            TunnelManager.shared.autoStart()
        }

        // Download model on first launch if needed (zero-config AI)
        ensureModel()
        // Auto-configure Claude Code settings (first launch)
        autoConfigureDevTools()

        // Auto-start llama-server with existing GGUF model
        Task.detached {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // プロキシ起動待ち
            let lcppPort = ModelRegistry.llamacppPortFast
            let alive = await HealthHandler.isAlive(port: lcppPort)
            guard !alive else { return }
            guard let ggufPath = SetupHandler.findExistingGGUF() else { return }
            let llamaServer = "/opt/homebrew/bin/llama-server"
            guard FileManager.default.fileExists(atPath: llamaServer) else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: llamaServer)
            p.arguments = ["-m", ggufPath, "--port", "\(lcppPort)", "-ngl", "99",
                           "--ctx-size", "4096", "--no-warmup", "-t", "4"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError  = FileHandle.nullDevice
            try? p.run()
            print("[NOU] llama-server 自動起動: \(URL(fileURLWithPath: ggufPath).lastPathComponent) port=\(lcppPort)")
        }

        // Auto-connect relay (nou.run) — if enabled in settings (default: ON for new installs)
        // Key: nou.relay.autoConnect — set by Network section toggle
        // Note: default is true so out-of-box experience works without configuration
        let relayAutoConnect = UserDefaults.standard.object(forKey: "nou.relay.autoConnect") == nil
            ? true  // first launch: ON by default
            : UserDefaults.standard.bool(forKey: "nou.relay.autoConnect")
        if relayAutoConnect {
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // wait for proxy server
                await RelayClient.shared.connect()
                print("[NOU] Connected to relay (nou.run)")
            }
        }

        // Register binary attestation with nou.run coordinator (provider side)
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // after relay connected
            let nodeID = UserDefaults.standard.string(forKey: "nou.depin.nodeID") ?? ""
            let apiKey = UserDefaults.standard.string(forKey: "nou.depin.apiKey") ?? ""
            await NOUAttestation.shared.registerSelf(nodeID: nodeID, apiKey: apiKey)
        }

        // Register sleep/wake notifications for recovery
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        // Register global hotkey ⌘⇧N for Quick AI panel
        registerQuickAIHotkey()

        // Run first-launch benchmark after backends have time to start
        Task.detached {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
            let mlxPort = ModelRegistry.portMain
            let llamacppPort = Int(ProcessInfo.processInfo.environment["LLAMACPP_PORT_MAIN"] ?? "5020") ?? 5020
            await RuntimeBenchmark.runIfNeeded(mlxPort: mlxPort, llamacppPort: llamacppPort)
        }

        // Auto-start Open WebUI (pip-installed, no Docker) after proxy is ready
        if UserDefaults.standard.object(forKey: "nou.openwebui.autoStart") == nil
            ? true : UserDefaults.standard.bool(forKey: "nou.openwebui.autoStart") {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // wait for proxy
                await OpenWebUIManager.shared.start()
            }
        }
    }

    // MARK: - Sleep / Wake Recovery

    @objc func handleSleep() {
        print("[NOU] Going to sleep...")
        publisher?.stop()
    }

    @objc func handleWake() {
        print("[NOU] Waking up, reconnecting...")
        // Re-start Bonjour advertisement (delay for network to come back)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.publisher?.start()
        }
        // Refresh all discovered nodes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            Task { @MainActor in
                self?.browser?.refreshAllNodes()
            }
        }
        // Restart tunnel if auto-start is enabled and it's not running
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            Task { @MainActor in
                let tunnel = TunnelManager.shared
                if !tunnel.isRunning {
                    tunnel.autoStart()
                }
            }
        }
        // Reconnect relay if enabled
        let shouldRelay = UserDefaults.standard.object(forKey: "nou.relay.autoConnect") == nil
            ? true : UserDefaults.standard.bool(forKey: "nou.relay.autoConnect")
        if shouldRelay {
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await RelayClient.shared.connect()
            }
        }
        // Restart llama-server if it died during sleep
        Task.detached {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            let lcppPort = ModelRegistry.llamacppPortFast
            guard !(await HealthHandler.isAlive(port: lcppPort)) else { return }
            guard let ggufPath = SetupHandler.findExistingGGUF() else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/llama-server")
            p.arguments = ["-m", ggufPath, "--port", "\(lcppPort)", "-ngl", "99",
                           "--ctx-size", "4096", "--no-warmup", "-t", "4"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError  = FileHandle.nullDevice
            try? p.run()
            print("[NOU] llama-server 復旧起動 (wake)")
        }
    }

    // MARK: - Quick AI Hotkey (⌃⌥N)

    private func registerQuickAIHotkey() {
        let hotKeyMods: NSEvent.ModifierFlags = [.control, .option]
        let hotKeyCode: UInt16 = 45 // N

        // When app is focused
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(hotKeyMods)
                && event.keyCode == hotKeyCode {
                Task { @MainActor in QuickAIPanel.shared.toggle() }
                return nil
            }
            return event
        }
        // When app is NOT focused (global) — requires Accessibility permission
        if AXIsProcessTrusted() {
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(hotKeyMods)
                    && event.keyCode == hotKeyCode {
                    Task { @MainActor in QuickAIPanel.shared.toggle() }
                }
            }
        } else {
            // プロンプトは初回のみ表示（バイナリ更新のたびに出ないよう制御）
            let promptedKey = "nou.ax.prompted"
            if !UserDefaults.standard.bool(forKey: promptedKey) {
                UserDefaults.standard.set(true, forKey: promptedKey)
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
            }
            print("[NOU] Accessibility permission needed for global hotkey ⌃⌥N")
        }
    }

    @MainActor
    func toggleQuickAI() {
        QuickAIPanel.shared.toggle()
    }

    // MARK: - Login Item (auto-start)

    private func registerLoginItem() {
        if #available(macOS 13.0, *) {
            let key = "nou.loginItem.registered"
            if !UserDefaults.standard.bool(forKey: key) {
                do {
                    try SMAppService.mainApp.register()
                    UserDefaults.standard.set(true, forKey: key)
                    print("[NOU] Registered as login item")
                } catch {
                    print("[NOU] Login item registration failed: \(error)")
                }
            }
        }
    }

    // MARK: - Auto-download optimal model on first launch (no bundled model needed)

    private func ensureModel() {
        let fm = FileManager.default
        let modelDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NOU/models")

        // If any GGUF already exists, skip
        let existing = (try? fm.contentsOfDirectory(atPath: modelDir.path))?.filter { $0.hasSuffix(".gguf") } ?? []
        if !existing.isEmpty {
            print("[NOU] Model already exists: \(existing.first ?? "")")
            return
        }

        // If bundled model exists in Resources, extract it as a quick-start fallback
        if let bundled = Bundle.main.url(forResource: "default-model", withExtension: "gguf") {
            let dest = modelDir.appendingPathComponent("bundled-model.gguf")
            do {
                try fm.createDirectory(at: modelDir, withIntermediateDirectories: true)
                try fm.copyItem(at: bundled, to: dest)
                print("[NOU] Extracted bundled model")
            } catch {
                print("[NOU] Bundled extraction failed: \(error)")
            }
        }

        // Download RAM-optimal model (runs immediately, not delayed)
        downloadOptimalModel()
    }

    /// Download models: fast 1.5B first (instant chat), then RAM-optimal in background
    private func downloadOptimalModel() {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let fm = FileManager.default
        let modelDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NOU/models")

        // unsloth/Qwen3 GGUFs — no HuggingFace auth required
        // Phase 1: Download Qwen3-1.7B FAST (~1.2GB) → instant chat
        let quickFile = "Qwen3-1.7B-Q4_K_M.gguf"
        let quickURL = "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf"

        // Phase 2: RAM-optimal model (background, after phase 1)
        let optimalFile: String?
        let optimalURL: String?
        if ramGB >= 32 {
            optimalFile = "Qwen3-14B-Q4_K_M.gguf"
            optimalURL = "https://huggingface.co/unsloth/Qwen3-14B-GGUF/resolve/main/Qwen3-14B-Q4_K_M.gguf"
        } else if ramGB >= 16 {
            optimalFile = "Qwen3-8B-Q4_K_M.gguf"
            optimalURL = "https://huggingface.co/unsloth/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf"
        } else if ramGB >= 8 {
            optimalFile = "Qwen3-4B-Q4_K_M.gguf"
            optimalURL = "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf"
        } else {
            optimalFile = nil; optimalURL = nil // 1.7B is good enough
        }

        Task.detached {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

            // Phase 1: quick model
            let quickDest = modelDir.appendingPathComponent(quickFile)
            if !FileManager.default.fileExists(atPath: quickDest.path) {
                print("[NOU] Phase 1: downloading \(quickFile) (~1GB)...")
                if await self.downloadFile(from: quickURL, to: quickDest) {
                    await self.startLlamaServer(modelPath: quickDest.path)
                    print("[NOU] Phase 1 complete — chat ready!")
                }
            }

            // Phase 2: optimal model (if different from quick)
            if let optFile = optimalFile, let optURL = optimalURL, optFile != quickFile {
                let optDest = modelDir.appendingPathComponent(optFile)
                if !FileManager.default.fileExists(atPath: optDest.path) {
                    print("[NOU] Phase 2: downloading \(optFile) for \(ramGB)GB RAM...")
                    if await self.downloadFile(from: optURL, to: optDest) {
                        // Restart llama-server with better model
                        await self.startLlamaServer(modelPath: optDest.path)
                        // Remove quick model to save disk
                        try? FileManager.default.removeItem(at: quickDest)
                        print("[NOU] Phase 2 complete — upgraded to \(optFile)")
                    }
                }
            }
        }
    }

    /// Download file using curl (progress visible, file appears immediately)
    private func downloadFile(from urlString: String, to dest: URL) async -> Bool {
        let curl = "/usr/bin/curl"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: curl)
        p.arguments = ["-fSL", "--progress-bar", "-o", dest.path, urlString]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                print("[NOU] curl failed with status \(p.terminationStatus)")
                return false
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
            print("[NOU] Downloaded: \(dest.lastPathComponent) (\(size / 1024 / 1024)MB)")
            return true
        } catch {
            print("[NOU] Download error: \(error)")
            return false
        }
    }

    private func startLlamaServer(modelPath: String) async {
        let llamaServer = "/opt/homebrew/bin/llama-server"
        guard FileManager.default.fileExists(atPath: llamaServer) else {
            print("[NOU] llama-server not found at \(llamaServer)")
            return
        }
        // Kill existing
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-f", "llama-server.*5021"]
        kill.standardOutput = FileHandle.nullDevice; kill.standardError = FileHandle.nullDevice
        try? kill.run(); kill.waitUntilExit()
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: llamaServer)
        p.arguments = ["-m", modelPath, "--port", "5021", "-ngl", "99", "--ctx-size", "4096", "--no-warmup", "-t", "4"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
        print("[NOU] Started llama-server with \(URL(fileURLWithPath: modelPath).lastPathComponent)")
    }

    // MARK: - Auto-configure Claude Code + dev tools (first launch, no user action needed)

    private func autoConfigureDevTools() {
        let key = "nou.devtools.configured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        Task.detached {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser.path

            // 1. Set ANTHROPIC_BASE_URL + OLLAMA_CONTEXT_LENGTH in shell RC
            let shellRCs = ["\(home)/.zshrc", "\(home)/.bashrc"]
            let shellRC = shellRCs.first { fm.fileExists(atPath: $0) } ?? "\(home)/.zshrc"

            var rcContent = (try? String(contentsOfFile: shellRC, encoding: .utf8)) ?? ""

            var additions: [String] = []
            if !rcContent.contains("ANTHROPIC_BASE_URL") {
                additions.append("export ANTHROPIC_BASE_URL=http://localhost:4004  # NOU Ollama proxy")
            }
            if !rcContent.contains("ANTHROPIC_API_KEY") {
                additions.append("export ANTHROPIC_API_KEY=sk-nou-local  # NOU auto-config")
            }
            if !rcContent.contains("OLLAMA_CONTEXT_LENGTH") {
                additions.append("export OLLAMA_CONTEXT_LENGTH=65536  # NOU auto-config")
            }

            if !additions.isEmpty {
                let block = "\n\n# NOU — ローカル AI 設定 (自動追加)\n" + additions.joined(separator: "\n") + "\n"
                if let fh = FileHandle(forWritingAtPath: shellRC) {
                    fh.seekToEndOfFile()
                    fh.write(block.data(using: .utf8)!)
                    fh.closeFile()
                } else {
                    // File doesn't exist yet — create it
                    try? block.write(toFile: shellRC, atomically: true, encoding: .utf8)
                }
                print("[NOU] Auto-configured \(shellRC): \(additions.count) env vars")
            }

            // 2. Set Claude Code KV cache optimization
            let claudeDir = "\(home)/.claude"
            let claudeSettings = "\(claudeDir)/settings.json"
            if !fm.fileExists(atPath: claudeDir) {
                try? fm.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
            }
            if fm.fileExists(atPath: claudeSettings) {
                if let data = fm.contents(atPath: claudeSettings),
                   var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if json["CLAUDE_CODE_ATTRIBUTION_HEADER"] == nil {
                        json["CLAUDE_CODE_ATTRIBUTION_HEADER"] = "0"
                        if let updated = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
                            try? updated.write(to: URL(fileURLWithPath: claudeSettings))
                            print("[NOU] Updated \(claudeSettings): CLAUDE_CODE_ATTRIBUTION_HEADER=0")
                        }
                    }
                }
            } else {
                let initial = #"{"CLAUDE_CODE_ATTRIBUTION_HEADER": "0"}"#
                try? initial.write(toFile: claudeSettings, atomically: true, encoding: .utf8)
                print("[NOU] Created \(claudeSettings)")
            }

            // 3. Mark as done
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: key)
            }
            print("[NOU] Dev tools auto-configured (Claude Code, Cursor, Aider ready)")
        }
    }
}
