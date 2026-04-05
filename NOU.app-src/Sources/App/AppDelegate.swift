import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var menubarController: MenubarController?
    var proxyServer: ProxyServer?
    var publisher: NOUPublisher?
    var browser: NOUBrowser?

    func applicationDidFinishLaunching(_ notification: Notification) {
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

        // Auto-connect DePIN relay if user enabled it
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // wait for proxy server
            if UserDefaults.standard.bool(forKey: "nou.relay.autoConnect") {
                await RelayClient.shared.connect()
                print("[NOU] Auto-connected DePIN relay")
            }
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
    }

    // MARK: - Quick AI Hotkey (⌘⇧N)

    private func registerQuickAIHotkey() {
        // When app is focused
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains([.command, .shift])
                && event.keyCode == 45 {
                Task { @MainActor in QuickAIPanel.shared.toggle() }
                return nil // consume the event
            }
            return event
        }
        // When app is NOT focused (global) — requires Accessibility permission
        if AXIsProcessTrusted() {
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains([.command, .shift])
                    && event.keyCode == 45 {
                    Task { @MainActor in QuickAIPanel.shared.toggle() }
                }
            }
        } else {
            // Prompt user for Accessibility permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            print("[NOU] Accessibility permission needed for global hotkey ⌘⇧N")
        }
    }

    @MainActor
    func toggleQuickAI() {
        QuickAIPanel.shared.toggle()
    }

    // MARK: - Login Item (auto-start)

    private func registerLoginItem() {
        if #available(macOS 13.0, *) {
            // Only register once (first launch)
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
}
