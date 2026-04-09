import AppKit
import ServiceManagement
import UserNotifications

// MARK: - i18n

private func L(_ ja: String, _ en: String) -> String {
    Locale.current.language.languageCode?.identifier == "ja" ? ja : en
}

// MARK: - MenubarController

@MainActor
class MenubarController {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var depinActive = false
    private var tunnelURL: String? = nil
    // Cached relay state (updated in refreshStatus)
    private var relayConnected = false
    private var relayPublicURL: String? = nil
    private var caffeinateProcess: Process? = nil
    private var proxyDownCount = 0
    private var browser: NOUBrowser?
    private var pulseTimer: Timer?
    private var pulseState = false
    private var currentTPS: Double = 0
    private var nodeRole: NodeRole = .unknown

    enum NodeRole {
        case server   // GPU backend alive (localhost:5000 responds)
        case relay    // No local GPU backend — proxy/remote only
        case unknown  // Not yet determined
    }

    private let mlxPorts: [(port: Int, key: String)] = [
        (5000, "main"), (5001, "fast"), (5002, "vision"), (4001, "proxy")
    ]

    /// NOU アイコンをメニューバーボタンに設定する
    private func setupMenubarIcon() {
        guard let button = statusItem.button else { return }
        // バンドル内の画像を優先、なければフォールバック絵文字
        if let img = NSImage(named: "NouMenubar") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true   // テンプレート: macOSがダーク/ライトモードに応じて色を自動調整
            button.image = img
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            button.title = "🧠"
        }
        // Left-click → Quick Chat; right-click → context menu
        button.action = #selector(statusItemClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // Show the context menu on right-click
            statusItem.menu = cachedMenu
            statusItem.button?.performClick(nil)
            // Remove menu after showing so left-click stays handled by action
            DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
        } else {
            // Left-click: quick chat popover
            QuickChatPopoverController.shared.toggle(relativeTo: sender)
        }
    }

    /// Cached context menu (rebuilt periodically)
    private var cachedMenu: NSMenu?

    init(browser: NOUBrowser? = nil) {
        self.browser = browser
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setupMenubarIcon()
        // Wire up the dashboard popover with the browser
        if let browser {
            DashboardPopoverController.shared.setBrowser(browser)
        }
        buildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        refreshStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.firstLaunchCheck()
        }
        // Check for updates in background after 15s
        Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await UpdateChecker.shared.checkForUpdates()
            await MainActor.run { [weak self] in
                if UpdateChecker.shared.isUpdateAvailable {
                    self?.buildMenu() // Rebuild to show update badge
                }
            }
        }
    }

    // MARK: - Menu Build

    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / (1024*1024*1024))
        let localTier = NodeTier.from(memoryGB: ramGB)

        // ── ① ヘッダー: NOU + ノード情報 ─────────────────
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: "  🧠  NOU  \(localTier.icon) \(localTier.rawValue) (\(ramGB)GB)",
            attributes: [.foregroundColor: NSColor.labelColor,
                         .font: NSFont.systemFont(ofSize: 13, weight: .bold)]
        )
        menu.addItem(header)

        // ── ② モデル稼働状態 (1行で全ポート表示) ─────────
        let statusRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusRow.isEnabled = false; statusRow.tag = 1000
        menu.addItem(statusRow)

        // ── ③ tok/s + リクエスト数 (推論中のみ表示) ──────
        let statsRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statsRow.isEnabled = false; statsRow.tag = 7777; statsRow.isHidden = true
        menu.addItem(statsRow)

        menu.addItem(.separator())

        // ── ④ よく使うAIツール (最重要アクション) ─────────
        let quickAIItem = NSMenuItem(
            title: L("  ⚡  Quick AI", "  ⚡  Quick AI"),
            action: #selector(openQuickAI), keyEquivalent: "N"
        )
        quickAIItem.keyEquivalentModifierMask = [.control, .option]
        quickAIItem.target = self
        menu.addItem(quickAIItem)

        addItem(menu, L("  🌐  ダッシュボード", "  🌐  Dashboard"), #selector(openDashboard), "d")
        addItem(menu, L("  💬  Chat (Open WebUI)", "  💬  Chat (Open WebUI)"), #selector(openChatUI), "o")
        addItem(menu, L("  📖  使い方・チュートリアル", "  📖  Getting Started"), #selector(openTutorial), "")

        menu.addItem(.separator())

        // ── ⑤ 起動 / 停止 / 再起動 ──────────────────────
        addItem(menu, L("  ▶  起動", "  ▶  Start"),   #selector(startAll),   "s")
        addItem(menu, L("  ↻  再起動", "  ↻  Restart"), #selector(restartAll), "r")
        addItem(menu, L("  ■  停止", "  ■  Stop"),    #selector(stopAll),    "x")

        menu.addItem(.separator())

        // ── ⑥ モデル選択 (現在のモデル名をインラインで表示) ─
        let modelMenu = NSMenu()
        let modelParent = NSMenuItem(title: L("  🧠  モデル", "  🧠  Model"), action: nil, keyEquivalent: "")
        modelParent.tag = 2000
        menu.addItem(modelParent)
        menu.setSubmenu(modelMenu, for: modelParent)
        buildModelSubmenu(modelMenu)

        // ── ⑦ ネットワーク (リモートノードを直接表示) ─────
        buildNetworkSection(menu)

        menu.addItem(.separator())

        // ── ⑧ 詳細サブメニュー (折りたたみ) ───────────────
        let distMenu = NSMenu()
        let distParent = NSMenuItem(
            title: L("  🖥️  複数Macで動かす", "  🖥️  Multi-Mac (Distributed)"),
            action: nil, keyEquivalent: ""
        )
        distParent.tag = 4000
        menu.addItem(distParent)
        menu.setSubmenu(distMenu, for: distParent)
        buildDistributedSubmenu(distMenu)

        let depinMenu = NSMenu()
        let depinParent = NSMenuItem(
            title: L("  🪙  GPU公開・報酬獲得 (DePIN)", "  🪙  Share GPU & Earn (DePIN)"),
            action: nil, keyEquivalent: ""
        )
        depinParent.tag = 3000
        menu.addItem(depinParent)
        menu.setSubmenu(depinMenu, for: depinParent)
        buildDepinSubmenu(depinMenu)

        let connectMenu = NSMenu()
        let connectParent = NSMenuItem(
            title: L("  🔗  ノードのペアリング", "  🔗  Pair Nodes"),
            action: nil, keyEquivalent: ""
        )
        menu.addItem(connectParent)
        menu.setSubmenu(connectMenu, for: connectParent)
        buildConnectSubmenu(connectMenu)

        // ── ⑨ ツール ────────────────────────────────────
        menu.addItem(.separator())
        addItem(menu, L("  💬  Claude Code...", "  💬  Claude Code..."), #selector(launchCld), "")
        addItem(menu, L("  🤖  Aider...", "  🤖  Aider..."), #selector(launchAider), "")

        // ── ⑩ 設定 / アップデート / 終了 ─────────────────
        menu.addItem(.separator())
        if UpdateChecker.shared.isUpdateAvailable, let v = UpdateChecker.shared.latestVersion {
            let updItem = NSMenuItem(
                title: L("  🆕  v\(v) にアップデート", "  🆕  Update to v\(v)"),
                action: #selector(openNativeSettings), keyEquivalent: ""
            )
            updItem.target = self
            updItem.attributedTitle = NSAttributedString(
                string: L("  🆕  v\(v) にアップデート", "  🆕  Update to v\(v)"),
                attributes: [.foregroundColor: NSColor.systemGreen,
                             .font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
            )
            menu.addItem(updItem)
        }
        addItem(menu, L("  ⚙️  設定...", "  ⚙️  Preferences..."), #selector(openNativeSettings), ",")
        addItem(menu, L("  ⏸  休止 (サーバー停止)", "  ⏸  Pause (stop server)"), #selector(pauseNOU), "")
        addItem(menu, L("  🗑  NOU をアンインストール", "  🗑  Uninstall NOU"), #selector(uninstallNOU), "")
        menu.addItem(.separator())
        addItem(menu, L("NOUを終了", "Quit NOU"), #selector(quit), "q")

        cachedMenu = menu
        // Don't attach menu directly — left-click is handled via statusItemClicked
    }

    private func buildNetworkSection(_ menu: NSMenu) {
        let netHeader = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        netHeader.isEnabled = false
        netHeader.attributedTitle = NSAttributedString(
            string: L("  🌐  ネットワーク", "  🌐  Network"),
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        )
        menu.addItem(netHeader)

        guard let browser else {
            addDisabled(menu, L("    検出中...", "    Searching..."))
            return
        }

        let remoteNodes = browser.nodes.filter { !$0.isLocal }
        if remoteNodes.isEmpty {
            addDisabled(menu, L("    リモートノードなし", "    No remote nodes found"))
        } else {
            for (ni, node) in remoteNodes.enumerated() {
                let dot = node.healthy ? "🟢" : "🔴"
                let rpcTag = node.rpcAvailable ? " [RPC]" : ""
                let pairTag = node.paired ? " \u{1F512}" : " \u{1F513}"  // locked / unlocked
                let tierIcon = node.tier.icon
                let memStr = node.memoryGB > 0 ? " \(node.memoryGB)GB" : ""
                let displayName = "\(dot) \(tierIcon) \(node.name)\(memStr)\(pairTag)\(rpcTag)"
                let nodeItem = NSMenuItem(title: displayName, action: nil, keyEquivalent: "")
                nodeItem.isEnabled = false
                nodeItem.attributedTitle = NSAttributedString(
                    string: "  \(displayName)",
                    attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
                )
                menu.addItem(nodeItem)

                if node.healthy {
                    for slot in node.models {
                        let rtIcon = slot.runtime == "llamacpp" ? "⚡" : "🍎"
                        let runDot = slot.running ? "●" : "○"

                        // Submenu for each slot
                        let slotMenu = NSMenu()

                        // Runtime toggle
                        let rtHeader = NSMenuItem(title: L("ランタイム", "Runtime"), action: nil, keyEquivalent: "")
                        rtHeader.isEnabled = false
                        slotMenu.addItem(rtHeader)

                        let lcppItem = NSMenuItem(
                            title: "\(slot.runtime == "llamacpp" ? "✓" : "  ") llama.cpp",
                            action: #selector(switchRemoteRuntime(_:)), keyEquivalent: ""
                        )
                        lcppItem.target = self
                        lcppItem.representedObject = ["url": node.url, "slot": slot.name, "runtime": "llamacpp"] as [String: Any]
                        slotMenu.addItem(lcppItem)

                        let mlxItem = NSMenuItem(
                            title: "\(slot.runtime == "mlx" ? "✓" : "  ") MLX",
                            action: #selector(switchRemoteRuntime(_:)), keyEquivalent: ""
                        )
                        mlxItem.target = self
                        mlxItem.representedObject = ["url": node.url, "slot": slot.name, "runtime": "mlx"] as [String: Any]
                        slotMenu.addItem(mlxItem)

                        slotMenu.addItem(.separator())

                        let benchItem = NSMenuItem(
                            title: L("▶ ベンチマーク", "▶ Benchmark"),
                            action: #selector(runRemoteBenchmark(_:)), keyEquivalent: ""
                        )
                        benchItem.target = self
                        benchItem.representedObject = ["url": node.url, "slot": slot.name] as [String: Any]
                        slotMenu.addItem(benchItem)

                        let slotItem = NSMenuItem(
                            title: "    \(runDot) \(slot.name): \(slot.label)  \(rtIcon) \(slot.runtime)",
                            action: nil, keyEquivalent: ""
                        )
                        menu.addItem(slotItem)
                        menu.setSubmenu(slotMenu, for: slotItem)
                    }

                    // Open dashboard on remote
                    let dashItem = NSMenuItem(
                        title: L("    🌐 ダッシュボード", "    🌐 Dashboard"),
                        action: #selector(openRemoteDashboard(_:)), keyEquivalent: ""
                    )
                    dashItem.target = self
                    dashItem.representedObject = node.url
                    menu.addItem(dashItem)

                    // Pair / Unpair
                    if node.paired {
                        let unpairItem = NSMenuItem(
                            title: L("    🔓 ペアリング解除", "    🔓 Unpair"),
                            action: #selector(unpairNode(_:)), keyEquivalent: ""
                        )
                        unpairItem.target = self
                        unpairItem.representedObject = ["url": node.url, "nodeID": node.nodeID, "name": node.name] as [String: Any]
                        menu.addItem(unpairItem)
                    } else if !node.nodeID.isEmpty {
                        let pairItem = NSMenuItem(
                            title: L("    🔐 ペアリング...", "    🔐 Pair..."),
                            action: #selector(pairNode(_:)), keyEquivalent: ""
                        )
                        pairItem.target = self
                        pairItem.representedObject = ["url": node.url, "nodeID": node.nodeID, "name": node.name] as [String: Any]
                        menu.addItem(pairItem)
                    }
                } else {
                    let offItem = NSMenuItem(title: L("    接続できません", "    Unreachable"), action: nil, keyEquivalent: "")
                    offItem.isEnabled = false
                    menu.addItem(offItem)
                }
            }
        }

        menu.addItem(.separator())

        // Add server manually
        let addItem = NSMenuItem(title: L("  ＋ サーバーを追加...", "  ＋ Add Server..."), action: #selector(addRemoteHost), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)
    }

    // MARK: - Network Actions

    @objc func switchRemoteRuntime(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let url = info["url"] as? String,
              let slot = info["slot"] as? String,
              let runtime = info["runtime"] as? String else { return }
        Task {
            let ok = await NOUAPIClient.switchRuntime(url: url, slot: slot, runtime: runtime)
            await MainActor.run { [weak self] in
                if ok {
                    self?.browser?.refreshAllNodes()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        self?.buildMenu()
                    }
                }
                self?.showAlert(
                    L("ランタイム変更", "Runtime Changed"),
                    ok ? "\(slot) → \(runtime)" : L("失敗しました", "Failed")
                )
            }
        }
    }

    @objc func runRemoteBenchmark(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let url = info["url"] as? String,
              let slot = info["slot"] as? String else { return }
        showAlert(L("ベンチマーク実行中...", "Benchmarking..."), "~30s")
        Task {
            let result = await NOUAPIClient.benchmark(url: url, slot: slot)
            await MainActor.run { [weak self] in
                if let r = result {
                    self?.showAlert(
                        L("ベンチマーク完了", "Benchmark Complete"),
                        "MLX: \(String(format: "%.0f", r.mlxGenTps)) tok/s\nllama.cpp: \(String(format: "%.0f", r.llamacppGenTps)) tok/s\nWinner: \(r.winner)"
                    )
                } else {
                    self?.showAlert(L("ベンチマーク失敗", "Benchmark Failed"), L("接続エラー", "Connection error"))
                }
                self?.browser?.refreshAllNodes()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.buildMenu()
                }
            }
        }
    }

    @objc func openRemoteDashboard(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(string: url)!)
    }

    @objc func fetchRemoteModels() {
        guard let browser else {
            showAlert(L("エラー", "Error"), L("ブラウザが未起動です", "Browser not started"))
            return
        }
        let remoteNodes = browser.nodes.filter { !$0.isLocal && $0.healthy }
        guard !remoteNodes.isEmpty else {
            showAlert(
                L("リモートノードなし", "No Remote Nodes"),
                L("ネットワーク上にNOUノードが見つかりません。", "No NOU nodes found on the network.")
            )
            return
        }
        Task {
            var allModels: [NOUAPIClient.RemoteModel] = []
            for node in remoteNodes {
                let models = await NOUAPIClient.availableModels(url: node.url)
                allModels.append(contentsOf: models.map {
                    NOUAPIClient.RemoteModel(name: $0.name, size: $0.size, type: $0.type,
                                              nodeURL: node.url, nodeName: node.name)
                })
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if allModels.isEmpty {
                    self.showAlert(
                        L("モデルなし", "No Models"),
                        L("リモートノードにモデルがありません。", "No models on remote nodes.")
                    )
                    return
                }
                let alert = NSAlert()
                alert.messageText = L("ネットワークモデル", "Network Models")
                let modelList = allModels.enumerated().map { (i, m) in
                    let sizeGB = String(format: "%.1f", Double(m.size) / 1_073_741_824.0)
                    return "\(i + 1). [\(m.type)] \(m.name) (\(sizeGB) GB) — \(m.nodeName)"
                }.joined(separator: "\n")
                alert.informativeText = L(
                    "ダウンロードするモデル番号を入力:\n\n\(modelList)",
                    "Enter model number to download:\n\n\(modelList)"
                )
                let tf = NSTextField(frame: NSRect(x: 0, y: 0, width: 60, height: 24))
                tf.placeholderString = "1"
                alert.accessoryView = tf
                alert.addButton(withTitle: L("ダウンロード", "Download"))
                alert.addButton(withTitle: L("キャンセル", "Cancel"))
                alert.window.initialFirstResponder = tf
                guard alert.runModal() == .alertFirstButtonReturn,
                      let idx = Int(tf.stringValue), idx >= 1, idx <= allModels.count else { return }
                let selected = allModels[idx - 1]
                let sizeGB = String(format: "%.1f", Double(selected.size) / 1_073_741_824.0)
                self.showAlert(
                    L("ダウンロード開始", "Download Started"),
                    "\(selected.name) (\(sizeGB) GB)\n\(L("完了時に通知します。", "You will be notified when done."))"
                )
                Task {
                    let ok: Bool
                    if selected.type == "mlx" {
                        ok = await NOUAPIClient.downloadMLX(
                            nodeURL: selected.nodeURL, modelName: selected.name) { _ in }
                    } else {
                        ok = await NOUAPIClient.downloadGGUF(
                            nodeURL: selected.nodeURL, filename: selected.name) { _ in }
                    }
                    await MainActor.run { [weak self] in
                        self?.showAlert(
                            ok ? L("ダウンロード完了", "Download Complete")
                               : L("ダウンロード失敗", "Download Failed"),
                            selected.name
                        )
                    }
                }
            }
        }
    }

    @objc func pairNode(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let url = info["url"] as? String,
              let name = info["name"] as? String else { return }
        Task {
            // Step 1: Send pairing request (remote shows PIN on their screen)
            let ok = await NOUAPIClient.sendPairRequest(url: url)
            guard ok else {
                await MainActor.run { [weak self] in
                    self?.showAlert(
                        L("ペアリング失敗", "Pairing Failed"),
                        L("リモートノードに接続できません。", "Could not connect to the remote node.")
                    )
                }
                return
            }

            // Step 2: Ask user to enter PIN shown on remote screen
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.promptInput(
                    L("PINを入力", "Enter PIN"),
                    L("\(name) に表示されている6桁のPINを入力してください", "Enter the 6-digit PIN shown on \(name)")
                ) { [weak self] pin in
                    Task {
                        // Step 3: Send PIN to confirm pairing
                        let result = await NOUAPIClient.confirmPairing(url: url, pin: pin)
                        await MainActor.run { [weak self] in
                            if result.success {
                                // Store the shared secret locally
                                PairingManager.shared.storePairing(
                                    remoteNodeID: result.remoteNodeID,
                                    secret: result.secret
                                )
                                self?.showAlert(
                                    L("ペアリング完了", "Pairing Complete"),
                                    L("\(name) とペアリングしました。", "Paired with \(name).")
                                )
                                self?.browser?.refreshAllNodes()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                                    self?.buildMenu()
                                }
                            } else {
                                self?.showAlert(
                                    L("ペアリング失敗", "Pairing Failed"),
                                    L("PINが正しくないか、有効期限が切れています。", "Invalid or expired PIN.")
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    @objc func unpairNode(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any],
              let nodeID = info["nodeID"] as? String,
              let name = info["name"] as? String else { return }

        let alert = NSAlert()
        alert.messageText = L("ペアリング解除", "Unpair")
        alert.informativeText = L(
            "\(name) とのペアリングを解除しますか？",
            "Unpair from \(name)?"
        )
        alert.addButton(withTitle: L("解除", "Unpair"))
        alert.addButton(withTitle: L("キャンセル", "Cancel"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        PairingManager.shared.unpair(nodeID)
        browser?.refreshAllNodes()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.buildMenu()
        }
    }

    @objc func addRemoteHost() {
        promptInput(
            L("NOU サーバーを追加", "Add NOU Server"),
            "http://192.168.0.10:4001"
        ) { [weak self] url in
            self?.browser?.addManualHost(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.buildMenu()
            }
        }
    }

    // MARK: - Distributed Inference Actions

    @objc func startLocalRPC() {
        Task {
            let (ok, message) = await DistributedInference.shared.startLocalRPC()
            await MainActor.run { [weak self] in
                self?.showAlert(
                    ok ? L("RPCワーカー起動", "RPC Worker Started") : L("エラー", "Error"),
                    message
                )
                self?.buildMenu()
            }
        }
    }

    @objc func stopLocalRPC() {
        Task {
            let message = await DistributedInference.shared.stopLocalRPC()
            await MainActor.run { [weak self] in
                self?.showAlert(L("RPCワーカー停止", "RPC Worker Stopped"), message)
                self?.buildMenu()
            }
        }
    }

    @objc func startRemoteRPC(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        Task {
            let ok = await NOUAPIClient.startRemoteRPC(url: url)
            await MainActor.run { [weak self] in
                self?.showAlert(
                    ok ? L("リモートRPC起動", "Remote RPC Started")
                       : L("エラー", "Error"),
                    ok ? "\(url)" : L("RPCサーバーが見つかりません", "RPC server binary not found on remote")
                )
                self?.browser?.refreshAllNodes()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.buildMenu() }
            }
        }
    }

    @objc func stopRemoteRPC(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        Task {
            _ = await NOUAPIClient.stopRemoteRPC(url: url)
            await MainActor.run { [weak self] in
                self?.browser?.refreshAllNodes()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.buildMenu() }
            }
        }
    }

    @objc func addNodeAsRPCWorker(_ sender: NSMenuItem) {
        guard let nodeURL = sender.representedObject as? String,
              let url = URL(string: nodeURL),
              let host = url.host else { return }
        Task {
            await DistributedInference.shared.addWorker(host: host, port: 50052)
            await DistributedInference.shared.refreshWorkers()
            await MainActor.run { [weak self] in
                self?.showAlert(
                    L("RPCワーカー追加", "RPC Worker Added"),
                    "\(host):50052"
                )
                self?.buildMenu()
            }
        }
    }

    @objc func addRPCWorkerManual() {
        promptInput(
            L("RPCワーカーを追加", "Add RPC Worker"),
            "192.168.0.5:50052"
        ) { [weak self] input in
            let parts = input.split(separator: ":")
            let host = String(parts[0])
            let port = parts.count > 1 ? Int(parts[1]) ?? 50052 : 50052
            Task {
                await DistributedInference.shared.addWorker(host: host, port: port)
                await DistributedInference.shared.refreshWorkers()
                await MainActor.run { [weak self] in
                    self?.buildMenu()
                }
            }
        }
    }

    @objc func toggleDistributed() {
        let current = UserDefaults.standard.bool(forKey: "nou.distributed.enabled")
        Task {
            await DistributedInference.shared.setDistributedEnabled(!current)
            await MainActor.run { [weak self] in
                self?.showAlert(
                    L("分散推論", "Distributed Inference"),
                    !current
                        ? L("有効にしました。再起動で反映されます。", "Enabled. Restart to apply.")
                        : L("無効にしました。再起動で反映されます。", "Disabled. Restart to apply.")
                )
                self?.buildMenu()
            }
        }
    }

    private func buildModelSubmenu(_ menu: NSMenu) {
        menu.autoenablesItems = false
        let currentMain  = ModelRegistry.activePreset(slot: "main")
        let currentFast  = ModelRegistry.activePreset(slot: "fast")
        let currentVision = ModelRegistry.activePreset(slot: "vision")

        // ── ランタイム切替 ────────────────────────────
        let currentRuntime = ModelRegistry.activeRuntime(slot: "main")
        addDisabled(menu, L("  ランタイム (Runtime)", "  Runtime"), size: 11)

        let llamaTitle = "  \(currentRuntime == .llamacpp ? "✓" : " ")  llama.cpp (\(L("高速", "Fast")))"
        let llamaItem = NSMenuItem(title: llamaTitle, action: #selector(selectRuntime(_:)), keyEquivalent: "")
        llamaItem.target = self; llamaItem.representedObject = "llamacpp"
        menu.addItem(llamaItem)

        let mlxTitle = "  \(currentRuntime == .mlx ? "✓" : " ")  MLX (Apple)"
        let mlxItem = NSMenuItem(title: mlxTitle, action: #selector(selectRuntime(_:)), keyEquivalent: "")
        mlxItem.target = self; mlxItem.representedObject = "mlx"
        menu.addItem(mlxItem)

        menu.addItem(.separator())

        addDisabled(menu, L("  メインモデル (高品質)", "  Main (Quality)"), size: 11)
        for p in ModelRegistry.presets.filter({ $0.slot == "main" }) {
            let item = NSMenuItem(title: "  \(p.id == currentMain.id ? "✓" : " ")  \(p.displayName)  (\(p.ramGB)GB)",
                                  action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = p.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addDisabled(menu, L("  高速モデル", "  Fast Model"), size: 11)
        for p in ModelRegistry.presets.filter({ $0.slot == "fast" }) {
            let item = NSMenuItem(title: "  \(p.id == currentFast.id ? "✓" : " ")  \(p.displayName)  (\(p.ramGB)GB)",
                                  action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = p.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addDisabled(menu, L("  ビジョン", "  Vision"), size: 11)
        for p in ModelRegistry.presets.filter({ $0.slot == "vision" }) {
            let item = NSMenuItem(title: "  \(p.id == currentVision.id ? "✓" : " ")  \(p.displayName)  (\(p.ramGB)GB)",
                                  action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = p.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("  ↻ モデル再起動", "  ↻ Restart with new model"), action: #selector(restartAll), keyEquivalent: ""))
        menu.items.last?.target = self
    }

    private func buildDepinSubmenu(_ menu: NSMenu) {
        menu.autoenablesItems = false

        // What is DePIN — brief explanation
        addDisabled(menu, L("  MacのGPUを公開→外部のAIリクエストを処理→報酬獲得", "  Share GPU → Process AI requests → Earn rewards"), size: 11)

        menu.addItem(.separator())

        addItemTo(menu, L("  🟢  公開ノードを開始", "  🟢  Start Public Node"), #selector(startDepin))
        addItemTo(menu, L("  🔴  公開ノードを停止", "  🔴  Stop Public Node"),  #selector(stopDepin))

        menu.addItem(.separator())

        // Reward info row (updated dynamically)
        let rewardItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        rewardItem.isEnabled = false
        rewardItem.tag = 3001
        rewardItem.attributedTitle = NSAttributedString(
            string: L("  🪙  獲得報酬: 読み込み中...", "  🪙  Earned: loading..."),
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        )
        menu.addItem(rewardItem)

        addItemTo(menu, L("  📊  ダッシュボードで詳細", "  📊  View in Dashboard"), #selector(openDashboard))
        addItemTo(menu, L("  🔑  接続URLをコピー", "  🔑  Copy Tunnel URL"), #selector(copyDepinInfo))
    }

    private func buildDistributedSubmenu(_ menu: NSMenu) {
        menu.autoenablesItems = false

        // Status header
        let statusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        statusItem.tag = 4001  // updated dynamically
        menu.addItem(statusItem)

        menu.addItem(.separator())

        // Local RPC worker controls
        addDisabled(menu, L("  このMacのRPCワーカー", "  This Mac's RPC Worker"), size: 11)
        addItemTo(menu, L("  ▶  RPCワーカー開始", "  ▶  Start RPC Worker"), #selector(startLocalRPC))
        addItemTo(menu, L("  ■  RPCワーカー停止", "  ■  Stop RPC Worker"),  #selector(stopLocalRPC))

        menu.addItem(.separator())

        // Remote RPC workers
        addDisabled(menu, L("  リモートRPCワーカー", "  Remote RPC Workers"), size: 11)

        if let browser {
            let remoteNodes = browser.nodes.filter { !$0.isLocal && $0.healthy }
            for node in remoteNodes {
                let rpcDot = node.rpcAvailable ? "●" : "○"
                let rpcLabel = node.rpcAvailable
                    ? L("RPC稼働中", "RPC Running")
                    : L("RPC停止", "RPC Stopped")

                let nodeMenu = NSMenu()

                let startRPC = NSMenuItem(
                    title: L("▶ RPCワーカー開始", "▶ Start RPC Worker"),
                    action: #selector(startRemoteRPC(_:)), keyEquivalent: ""
                )
                startRPC.target = self
                startRPC.representedObject = node.url
                nodeMenu.addItem(startRPC)

                let stopRPC = NSMenuItem(
                    title: L("■ RPCワーカー停止", "■ Stop RPC Worker"),
                    action: #selector(stopRemoteRPC(_:)), keyEquivalent: ""
                )
                stopRPC.target = self
                stopRPC.representedObject = node.url
                nodeMenu.addItem(stopRPC)

                nodeMenu.addItem(.separator())

                let addAsWorker = NSMenuItem(
                    title: L("+ ワーカーとして追加", "+ Add as Worker"),
                    action: #selector(addNodeAsRPCWorker(_:)), keyEquivalent: ""
                )
                addAsWorker.target = self
                addAsWorker.representedObject = node.url
                nodeMenu.addItem(addAsWorker)

                let nodeItem = NSMenuItem(
                    title: "  \(rpcDot) \(node.name) — \(rpcLabel)",
                    action: nil, keyEquivalent: ""
                )
                menu.addItem(nodeItem)
                menu.setSubmenu(nodeMenu, for: nodeItem)
            }

            if remoteNodes.isEmpty {
                addDisabled(menu, L("    リモートノードなし", "    No remote nodes found"))
            }
        }

        menu.addItem(.separator())

        // Manual worker add
        addItemTo(menu, L("  ＋ RPCワーカーを追加...", "  + Add RPC Worker..."), #selector(addRPCWorkerManual))

        menu.addItem(.separator())

        // Enable/disable distributed mode
        let distEnabled = UserDefaults.standard.bool(forKey: "nou.distributed.enabled")
        let toggleTitle = distEnabled
            ? L("  ✓ 分散推論: 有効", "  ✓ Distributed: ON")
            : L("     分散推論: 無効", "     Distributed: OFF")
        addItemTo(menu, toggleTitle, #selector(toggleDistributed))

        // Update status line
        Task {
            let status = await DistributedInference.shared.status()
            await MainActor.run {
                let onlineCount = status.workers.filter { $0.status == .online }.count
                let totalCount = status.workers.count
                let localStr = status.localRPCRunning
                    ? L("ローカルRPC: ●", "Local RPC: ●")
                    : L("ローカルRPC: ○", "Local RPC: ○")
                let workersStr = L("ワーカー: \(onlineCount)/\(totalCount)", "Workers: \(onlineCount)/\(totalCount)")
                statusItem.attributedTitle = NSAttributedString(
                    string: "  \(localStr)  \(workersStr)",
                    attributes: [
                        .foregroundColor: onlineCount > 0 ? NSColor.systemGreen : NSColor.secondaryLabelColor,
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                    ]
                )
            }
        }
    }

    private func buildConnectSubmenu(_ menu: NSMenu) {
        menu.autoenablesItems = false

        // Relay toggle (nou.run — always on)
        let autoTunnelItem = NSMenuItem(
            title: L("  🌐  NOU Relay (nou.run)", "  🌐  NOU Relay (nou.run)"),
            action: #selector(toggleAutoTunnel),
            keyEquivalent: ""
        )
        autoTunnelItem.target = self
        autoTunnelItem.tag = 6000
        autoTunnelItem.state = .on   // relay is always auto-connected
        menu.addItem(autoTunnelItem)

        // Tunnel URL display (hidden when no tunnel)
        let tunnelURLItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        tunnelURLItem.isEnabled = false
        tunnelURLItem.tag = 6001
        tunnelURLItem.isHidden = true
        menu.addItem(tunnelURLItem)

        addItemTo(menu, L("  🚇  Tunnel開始",        "  🚇  Start Tunnel"),     #selector(startTunnel))
        addItemTo(menu, L("  🚫  Tunnel停止",         "  🚫  Stop Tunnel"),      #selector(stopTunnel))
        menu.addItem(.separator())
        addItemTo(menu, L("  📋  リモートURLをコピー","  📋  Copy Remote URL"),  #selector(copyRemoteURL))
        addItemTo(menu, L("  📋  LAN URLをコピー",    "  📋  Copy LAN URL"),     #selector(copyURL))
        menu.addItem(.separator())
        addItemTo(menu, L("  🌐  Auto-Proxy設定",     "  🌐  Enable Auto-Proxy"), #selector(openProxySettings))
        menu.addItem(.separator())
        addItemTo(menu, L("  💬  Claude Code (クラウド)", "  💬  Claude Code (Cloud)"), #selector(launchClc))
    }

    private func buildSettingsSubmenu(_ menu: NSMenu) {
        menu.autoenablesItems = false
        // 開発ツール
        addDisabled(menu, "  開発ツール", bold: true, size: 11)
        addItemTo(menu, L("  💬  Claude Code", "  💬  Claude Code"), #selector(launchCld))
        addItemTo(menu, L("  🤖  Aider", "  🤖  Aider"), #selector(launchAider))
        menu.addItem(.separator())
        // ベータ機能
        addDisabled(menu, "  ベータ機能", bold: true, size: 11)
        let bbKey = "nou.beta.blackboard"
        let bbEnabled = UserDefaults.standard.bool(forKey: bbKey)
        let bbItem = NSMenuItem(
            title: L(
                "  📋  Blackboard (エージェント知識共有) \(bbEnabled ? "✓" : "")",
                "  📋  Blackboard (Agent Knowledge) \(bbEnabled ? "✓" : "")"
            ),
            action: #selector(toggleBlackboard), keyEquivalent: ""
        )
        bbItem.target = self
        menu.addItem(bbItem)
        menu.addItem(.separator())
        // ユーティリティ
        addItemTo(menu, L("  🖼  画像を生成...", "  🖼  Generate Image..."), #selector(genImage))
        addItemTo(menu, L("  🎬  動画を生成...", "  🎬  Generate Video..."), #selector(genVideo))
        addItemTo(menu, L("  ⚡  ベンチマーク", "  ⚡  Benchmark"), #selector(runBench))
        addItemTo(menu, L("  📄  ログを開く", "  📄  Open Logs"), #selector(openLogs))
        addItemTo(menu, L("  🖥  ターミナル", "  🖥  Terminal"), #selector(openTerminal))
        menu.addItem(.separator())
        addItemTo(menu, L("  📦  GitHubを開く", "  📦  GitHub"), #selector(openGitHub))
        addItemTo(menu, L("  ✓  ヘルスチェック", "  ✓  Health Check"), #selector(healthCheck))
    }

    @objc func toggleBlackboard() {
        let key = "nou.beta.blackboard"
        let current = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(!current, forKey: key)
        buildMenu()
    }

    // MARK: - Helpers

    private func addDisabled(_ menu: NSMenu, _ title: String, bold: Bool = false,
                              color: NSColor = .secondaryLabelColor, size: CGFloat = 12) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: bold ? NSFont.systemFont(ofSize: size, weight: .bold)
                        : NSFont.systemFont(ofSize: size, weight: .regular)
        ])
        menu.addItem(item)
    }

    private func addItem(_ menu: NSMenu, _ title: String, _ sel: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        item.target = self; menu.addItem(item)
    }

    private func addItemTo(_ menu: NSMenu, _ title: String, _ sel: Selector) {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }

    // MARK: - Menubar Icon Animation

    private var roleIcon: String { "" }  // 画像アイコン使用のため不使用

    private func updateMenubarIcon(tps: Double) {
        currentTPS = tps
        if tps > 0.5 {
            startPulse()
        } else {
            stopPulse()
            // Show "!" badge if setup incomplete (no model running after 30s)
            checkSetupBadge()
        }
    }

    private var setupBadgeTimer: Timer? = nil
    private func checkSetupBadge() {
        // Only show badge if proxy is not responding (setup not complete)
        guard pulseTimer == nil else { return }
        let proxyAlive = Self.isPortAlive(4001)
        guard let button = statusItem.button else { return }
        if !proxyAlive {
            // Orange exclamation badge on the icon
            let badgeAttr = NSAttributedString(string: " !", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 9),
                .foregroundColor: NSColor.systemOrange,
                .baselineOffset: 4
            ])
            button.attributedTitle = badgeAttr
            if let img = NSImage(named: "NouMenubar") {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = true
                button.image = img
                button.imagePosition = .imageLeft
            }
        } else {
            // Clear badge if proxy is running
            if button.attributedTitle.string == " !" {
                button.attributedTitle = NSAttributedString()
                setupMenubarIconImage()
            }
        }
    }

    private func setupMenubarIconImage() {
        guard let button = statusItem.button else { return }
        if let img = NSImage(named: "NouMenubar") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
            button.title = ""
        }
    }

    private func startPulse() {
        guard pulseTimer == nil else { return }
        applyPulseFrame()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.applyPulseFrame() }
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseState = false
        statusItem.button?.attributedTitle = NSAttributedString()
        setupMenubarIcon()
    }

    private func applyPulseFrame() {
        pulseState.toggle()
        let tpsStr = currentTPS >= 10 ? String(Int(currentTPS)) : String(format: "%.1f", currentTPS)
        let opacity: CGFloat = pulseState ? 1.0 : 0.35
        // TPS テキストだけ attributedTitle に入れ、image は維持
        let tpsAttr = NSAttributedString(string: " \(tpsStr)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.systemGreen.withAlphaComponent(opacity),
            .baselineOffset: 2
        ])
        statusItem.button?.attributedTitle = tpsAttr
        // 画像を再セット（attributedTitle が上書きするので）
        if let img = NSImage(named: "NouMenubar") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            statusItem.button?.image = img
            statusItem.button?.imagePosition = .imageLeft
        }
    }

    /// Build a compact status string for the status row (tag 1000).
    /// Format:  ● 122B  ● 35B  ○ VL  ● Proxy
    func makeStatusRowTitle(portResults: [(Int, String, Bool)]) -> NSAttributedString {
        // Map port → display label
        let portLabel: [Int: String] = [5000: "122B", 5001: "35B", 5002: "VL", 4001: "Proxy"]
        let parts = portResults.map { (port, _, alive) -> NSAttributedString in
            let dot = alive ? "●" : "○"
            let label = portLabel[port] ?? "?"
            let color: NSColor = alive ? .systemGreen : .tertiaryLabelColor
            return NSAttributedString(string: "\(dot) \(label)", attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            ])
        }
        let joined = NSMutableAttributedString(string: "  ")
        for (i, part) in parts.enumerated() {
            joined.append(part)
            if i < parts.count - 1 {
                joined.append(NSAttributedString(
                    string: "  ",
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
                ))
            }
        }
        return joined
    }

    // MARK: - Status Refresh

    func refreshStatus() {
        Task.detached { [weak self] in
            guard let self else { return }
            var portResults: [(Int, String, Bool)] = []
            for entry in await self.mlxPorts {
                portResults.append((entry.port, entry.key, Self.isPortAlive(entry.port)))
            }
            // Fetch relay state from actor
            let relaySnap = await RelayClient.shared.snapshot
            let relayConn = relaySnap["connected"] as? Bool ?? false
            let relayURL  = relaySnap["public_url"] as? String ?? ""
            let depinRunning = await self.depinActive || relayConn
            let idleSecs = Self.getIdleSeconds()
            let isIdle = idleSecs >= 300

            // /api/stats
            var tokPerSec = "0.0"; var totalReqs = 0; var depinReqs = 0
            if portResults.first(where: { $0.0 == 4001 })?.2 == true,
               let url = URL(string: "http://127.0.0.1:4001/api/stats"),
               let (d, _) = try? await URLSession.shared.data(from: url),
               let stats = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                tokPerSec = stats["tok_per_sec"] as? String ?? "0.0"
                totalReqs = stats["total_requests"] as? Int ?? 0
                depinReqs = stats["depin_requests"] as? Int ?? 0
            }

            let running = portResults.filter { $0.2 }.count
            let proxyAlive = portResults.first(where: { $0.0 == 4001 })?.2 ?? false
            // Determine node role: server if any GPU backend port (5000/5001/5002) is alive
            let gpuAlive = portResults.contains { $0.0 != 4001 && $0.2 }

            let rewardCU = await RewardLedger.shared.computeUnits

            await MainActor.run { [weak self] in
                guard let self else { return }
                // Update node role
                self.nodeRole = gpuAlive ? .server : .relay

                // Auto-recovery
                if !proxyAlive {
                    self.proxyDownCount += 1
                    if self.proxyDownCount >= 2 {
                        self.proxyDownCount = 0
                        self.runShell("~/ai.sh start 2>/dev/null || true")
                    }
                } else { self.proxyDownCount = 0 }

                // アイコン: inference中は tok/s 表示 + パルス
                self.updateMenubarIcon(tps: Double(tokPerSec) ?? 0)

                guard let menu = self.statusItem.menu else { return }

                // ステータス行 (tag 1000) — 各ポートの色付きドット表示
                if let statusItem = menu.items.first(where: { $0.tag == 1000 }) {
                    statusItem.attributedTitle = self.makeStatusRowTitle(portResults: portResults)
                }

                // 統計行 (tag 7777)
                if let statsItem = menu.items.first(where: { $0.tag == 7777 }) {
                    if totalReqs > 0 || (Double(tokPerSec) ?? 0) > 0 {
                        statsItem.isHidden = false
                        var text = "  ⚡ \(tokPerSec) tok/s · \(totalReqs) req"
                        if depinReqs > 0 { text += " · 🌍 \(depinReqs) DePIN" }
                        if depinRunning {
                            text += isIdle ? "  💰" : "  🟢"
                        }
                        statsItem.attributedTitle = NSAttributedString(
                            string: text,
                            attributes: [.foregroundColor: NSColor.systemBlue,
                                         .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
                        )
                    } else { statsItem.isHidden = true }
                }

                // モデルメニュー表示名を更新 (tag 2000)
                if let modelItem = menu.items.first(where: { $0.tag == 2000 }) {
                    let preset = ModelRegistry.activePreset(slot: "main")
                    modelItem.title = L("  🧠  \(preset.displayName)", "  🧠  \(preset.displayName)")
                }

                // DePIN親メニュー更新 (tag 3000)
                if let depinItem = menu.items.first(where: { $0.tag == 3000 }) {
                    let status = depinRunning ? (isIdle ? "💰" : "🟢") : ""
                    depinItem.title = L("  🪙  GPU公開・報酬獲得 (DePIN)  \(status)", "  🪙  Share GPU & Earn (DePIN)  \(status)")
                }

                // 報酬情報更新 (tag 3001) — DePINサブメニュー内
                let cu = rewardCU
                let nou = Double(cu) / 1000.0
                if let rewardMenuItem = menu.items
                    .compactMap({ $0.submenu?.items.first(where: { $0.tag == 3001 }) })
                    .first {
                    let cuStr = cu.formatted()
                    rewardMenuItem.attributedTitle = NSAttributedString(
                        string: L("  🪙  獲得報酬: \(cuStr) CU ≈ \(String(format:"%.3f",nou)) NOU",
                                  "  🪙  Earned: \(cuStr) CU ≈ \(String(format:"%.3f",nou)) NOU"),
                        attributes: [.font: NSFont.systemFont(ofSize: 12),
                                     .foregroundColor: cu > 0 ? NSColor.systemGreen : NSColor.secondaryLabelColor]
                    )
                }

                // Relay URL display (tag 6001) — sync from RelayClient
                self.relayConnected = relayConn
                self.relayPublicURL = relayURL.isEmpty ? nil : relayURL
                self.tunnelURL = self.relayPublicURL
                if let urlItem = menu.items.first(where: { $0.tag == 6001 }) {
                    if let rURL = self.relayPublicURL {
                        urlItem.isHidden = false
                        urlItem.attributedTitle = NSAttributedString(
                            string: "    \(rURL)",
                            attributes: [.foregroundColor: NSColor.systemBlue,
                                         .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
                        )
                    } else {
                        urlItem.isHidden = true
                    }
                }
                // Auto-Relay checkmark (tag 6000) — relay is always on, show as checked
                if let autoItem = menu.items.first(where: { $0.tag == 6000 }) {
                    autoItem.state = .on
                }
            }
        }
    }

    // MARK: - Static helpers

    nonisolated static func isPortAlive(_ port: Int) -> Bool {
        let urlStr = port == 4001 ? "http://127.0.0.1:\(port)/health"
                                  : "http://127.0.0.1:\(port)/v1/models"
        guard let url = URL(string: urlStr) else { return false }
        var req = URLRequest(url: url, timeoutInterval: 2)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0); var alive = false
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            alive = (resp as? HTTPURLResponse)?.statusCode == 200; sem.signal()
        }.resume(); sem.wait(); return alive
    }

    nonisolated static func isProcessRunning(_ name: String) -> Bool {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", name]; p.standardOutput = pipe
        try? p.run(); p.waitUntilExit(); return p.terminationStatus == 0
    }

    nonisolated static func getIdleSeconds() -> Double {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "ioreg -c IOHIDSystem | awk '/HIDIdleTime/{print $NF/1000000000; exit}'"]
        p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return Double(String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
    }

    nonisolated static func which(_ cmd: String) -> String? {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [cmd]; p.standardOutput = pipe; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }

    // MARK: - Sleep

    private func preventSleep() {
        guard caffeinateProcess == nil else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-i"]; try? p.run(); caffeinateProcess = p
    }

    private func allowSleep() { caffeinateProcess?.terminate(); caffeinateProcess = nil }

    // MARK: - Shell

    func runShell(_ cmd: String, completion: ((String) -> Void)? = nil) {
        DispatchQueue.global().async {
            let p = Process(); let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "export PATH=/opt/homebrew/bin:$HOME/.cargo/bin:$PATH\n\(cmd)"]
            p.standardOutput = pipe; p.standardError = pipe
            try? p.run(); p.waitUntilExit()
            completion?(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        }
    }

    func showAlert(_ title: String, _ msg: String) {
        DispatchQueue.main.async {
            let a = NSAlert(); a.messageText = title; a.informativeText = msg; a.runModal()
        }
    }

    func askRestart(_ title: String, _ detail: String) {
        DispatchQueue.main.async {
            let a = NSAlert()
            a.messageText     = title
            a.informativeText = detail
            a.addButton(withTitle: L("今すぐ再起動", "Restart Now"))
            a.addButton(withTitle: L("後で", "Later"))
            if a.runModal() == .alertFirstButtonReturn {
                let url = Bundle.main.bundleURL
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = [url.path]
                try? task.run()
                NSApp.terminate(nil)
            }
        }
    }

    func promptInput(_ title: String, _ placeholder: String, completion: @escaping (String) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert(); alert.messageText = title
            let tf = NSTextField(frame: NSRect(x:0,y:0,width:380,height:24))
            tf.placeholderString = placeholder; alert.accessoryView = tf
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: L("キャンセル","Cancel"))
            alert.window.initialFirstResponder = tf
            if alert.runModal() == .alertFirstButtonReturn, !tf.stringValue.isEmpty {
                completion(tf.stringValue)
            }
        }
    }

    func getLANIP() -> String {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/ipconfig")
        p.arguments = ["getifaddr", "en0"]; p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "127.0.0.1"
    }

    func getAPIKey() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return (try? String(contentsOf: home.appendingPathComponent(".local-ai-key"),
            encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "sk-ant-dummy"
    }

    private func openTerminalWith(_ cmd: String) {
        let escaped = cmd.replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"Terminal\" to do script \"\(escaped)\""]
        try? p.run()
    }

    // MARK: - First Launch

    private func firstLaunchCheck() {
        guard !UserDefaults.standard.bool(forKey: "nou.launched.v4") else { return }
        UserDefaults.standard.set(true, forKey: "nou.launched.v4")
        // No welcome window — just silently set up everything.
        // Show "preparing..." in menubar, notify when ready.
        statusItem.button?.title = "⏳"
        monitorModelReady()
    }

    /// Poll until llama-server is ready, then flip the menubar icon and notify
    private func monitorModelReady() {
        Task { @MainActor in
            for _ in 0..<360 { // up to 30 min
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if let url = URL(string: "http://127.0.0.1:5021/v1/models"),
                   let (_, resp) = try? await URLSession.shared.data(from: url),
                   (resp as? HTTPURLResponse)?.statusCode == 200 {
                    // Ready!
                    statusItem.button?.title = "🧠"
                    sendReadyNotification()
                    return
                }
            }
            // Timeout — still show brain icon
            statusItem.button?.title = "🧠"
        }
    }

    private func sendReadyNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "NOU — AI 準備完了"
        content.body = "メニューバーの 🧠 をクリックしてチャットを始められます。"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "nou.ready", content: content, trigger: nil)
        center.add(req) { _ in }
    }

    @objc func openTutorial() {
        // Open the full interactive tutorial in the default browser
        if let url = URL(string: "http://localhost:4001/tutorial") {
            NSWorkspace.shared.open(url)
        }
        // Also open the settings guide panel as a fallback
        NOUSettingsWindowController.shared.showSettings()
        NOUSettingsWindowController.shared.showSection("guide")
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions: Control

    @objc func startAll() {
        setupMenubarIcon()
        // ai.sh があれば使う（開発者環境）、なければ直接起動
        let aiSh = NSHomeDirectory() + "/ai.sh"
        if FileManager.default.fileExists(atPath: aiSh) {
            runShell("'\(aiSh)' start") { [weak self] out in
                Task { @MainActor in
                    self?.refreshStatus()
                    if !out.isEmpty { self?.showAlert(L("起動","Started"), out) }
                }
            }
        } else {
            // プロキシサーバー経由でMLXサーバーを起動
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let url = URL(string: "http://localhost:4001/api/setup/start-mlx-server") else { return }
                var req = URLRequest(url: url); req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: [:])
                _ = try? await URLSession.shared.data(for: req)
                self.refreshStatus()
                self.showAlert(L("起動","Start"), L("MLXサーバーを起動しました","MLX server started"))
            }
        }
    }

    @objc func stopAll() {
        let aiSh = NSHomeDirectory() + "/ai.sh"
        if FileManager.default.fileExists(atPath: aiSh) {
            runShell("'\(aiSh)' stop") { [weak self] _ in
                Task { @MainActor in self?.setupMenubarIcon(); self?.refreshStatus() }
            }
        } else {
            // mlx_lm.server プロセスを直接停止
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            p.arguments = ["-f", "mlx_lm.server"]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                Task { @MainActor in self?.setupMenubarIcon(); self?.refreshStatus() }
            }
        }
    }

    @objc func restartAll() {
        setupMenubarIcon()
        let aiSh = NSHomeDirectory() + "/ai.sh"
        if FileManager.default.fileExists(atPath: aiSh) {
            runShell("'\(aiSh)' restart") { [weak self] _ in
                Task { @MainActor in self?.refreshStatus() }
            }
        } else {
            // stop → 1s 待機 → start
            let stop = Process()
            stop.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            stop.arguments = ["-f", "mlx_lm.server"]
            stop.standardOutput = FileHandle.nullDevice; stop.standardError = FileHandle.nullDevice
            try? stop.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.startAll()
            }
        }
    }

    @objc func healthCheck() {
        let aiSh = NSHomeDirectory() + "/ai.sh"
        if FileManager.default.fileExists(atPath: aiSh) {
            runShell("'\(aiSh)' health 2>/dev/null || echo '...'") { [weak self] out in
                Task { @MainActor in
                    self?.refreshStatus()
                    self?.showAlert(L("ヘルスチェック","Health Check"), out.isEmpty ? L("正常","OK") : out)
                }
            }
        } else {
            // ポートの稼働状況を直接確認
            Task { @MainActor [weak self] in
                guard let self else { return }
                let ports = [(4001, "Proxy"), (5000, "MLX Main"), (5001, "MLX Fast"), (5002, "MLX Vision")]
                var lines: [String] = []
                for (port, name) in ports {
                    let alive = Self.isPortAlive(port)
                    lines.append("\(alive ? "✅" : "⭕") \(name) :\(port)")
                }
                self.refreshStatus()
                self.showAlert(L("ヘルスチェック","Health Check"), lines.joined(separator: "\n"))
            }
        }
    }

    // MARK: - Actions: Model Select

    @objc func selectModel(_ sender: NSMenuItem) {
        guard let presetID = sender.representedObject as? String,
              let preset = ModelRegistry.presets.first(where: { $0.id == presetID }) else { return }
        ModelRegistry.setActiveModel(slot: preset.slot, presetID: presetID)
        buildMenu()  // メニューを再構築して ✓ を更新
        askRestart(
            L("モデルを変更しました", "Model Changed"),
            L("今すぐ再起動して \(preset.displayName) を有効にしますか？",
              "Restart now to activate \(preset.displayName)?")
        )
    }

    @objc func selectRuntime(_ sender: NSMenuItem) {
        guard let rtString = sender.representedObject as? String,
              let runtime = BackendConfig.Runtime(rawValue: rtString) else { return }
        ModelRegistry.setActiveRuntime(slot: "main", runtime: runtime)
        buildMenu()
        askRestart(
            L("ランタイムを変更しました", "Runtime Changed"),
            L("今すぐ再起動して \(rtString) を有効にしますか？",
              "Restart now to activate \(rtString)?")
        )
    }

    // MARK: - Actions: AI Tools

    @objc func launchCld() {
        openTerminalWith("export PATH=/opt/homebrew/bin:$PATH && export ANTHROPIC_BASE_URL=http://127.0.0.1:4001 && export ANTHROPIC_API_KEY=sk-ant-dummy && claude --dangerously-skip-permissions")
    }

    @objc func launchClc() {
        openTerminalWith("export PATH=/opt/homebrew/bin:$PATH && unset ANTHROPIC_BASE_URL && claude")
    }

    @objc func launchAider() {
        openTerminalWith("export PATH=/opt/homebrew/bin:$PATH && source ~/mlx_env/bin/activate && OPENAI_API_BASE=http://127.0.0.1:4001/v1 OPENAI_API_KEY=sk-dummy aider --model openai/qwen3.5-122b")
    }

    @objc func openTerminal() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    @objc func openDashboard() {
        guard let button = statusItem.button else {
            // Fallback: open web dashboard in browser
            NSWorkspace.shared.open(URL(string: "http://127.0.0.1:4001/")!)
            return
        }
        DashboardPopoverController.shared.toggle(relativeTo: button)
    }

    @objc func openQuickAI() {
        QuickAIPanel.shared.toggle()
    }

    @objc func openChatUI() {
        Task {
            let mgr = OpenWebUIManager.shared
            let installed = await mgr.isInstalled
            if !installed {
                OpenWebUIManager.showInstallInstructions()
                return
            }
            let running = await mgr.isRunning
            let starting = await mgr.isStarting
            if !running && !starting {
                // Start if not yet running
                Task { await OpenWebUIManager.shared.start() }
                // Brief delay then open browser
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            await mgr.openInBrowser()
        }
    }

    // MARK: - Actions: Generate

    @objc func genImage() {
        let aiSh = NSHomeDirectory() + "/ai.sh"
        if FileManager.default.fileExists(atPath: aiSh) {
            promptInput(L("画像プロンプト","Image Prompt"), "a cyberpunk Tokyo street at night") { [weak self] prompt in
                self?.showAlert(L("生成中...","Generating..."), L("約17秒","~17 seconds"))
                let escaped = prompt.replacingOccurrences(of: "\"", with: "\\\"")
                self?.runShell("'\(aiSh)' img \"\(escaped)\"") { _ in
                    self?.showAlert(L("完成！","Done!"), "~/generated/")
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated"))
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "http://localhost:4001")!)
        }
    }

    @objc func genVideo() {
        let aiSh = NSHomeDirectory() + "/ai.sh"
        if FileManager.default.fileExists(atPath: aiSh) {
            promptInput(L("動画プロンプト","Video Prompt"), "samurai on a cliff, sunset") { [weak self] prompt in
                self?.showAlert(L("生成中...","Generating..."), L("約10分","~10 min"))
                let escaped = prompt.replacingOccurrences(of: "\"", with: "\\\"")
                self?.runShell("'\(aiSh)' vid \"\(escaped)\"") { _ in
                    self?.showAlert(L("完成！","Done!"), "~/generated/")
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated"))
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(URL(string: "http://localhost:4001")!)
        }
    }

    // MARK: - Actions: DePIN

    @objc func startDepin() {
        depinActive = true; preventSleep(); setupMenubarIcon()
        Task {
            await RelayClient.shared.connect()
            // Wait up to 10s for relay URL
            var tunnelURL: String? = nil
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let snap = await RelayClient.shared.snapshot
                if let u = snap["public_url"] as? String, !u.isEmpty {
                    tunnelURL = u; break
                }
            }
            guard let tunnelURL else {
                await MainActor.run {
                    self.depinActive = false; self.allowSleep()
                    self.showAlert(L("エラー","Error"), "nou.run への接続に失敗しました")
                }
                return
            }
            self.registerNode(tunnelURL: tunnelURL)
        }
    }

    private func registerNode(tunnelURL: String) {
        let nodeID = UserDefaults.standard.string(forKey: "nou.depin.nodeID") ?? {
            let n = "nou-\(UUID().uuidString.prefix(8).lowercased())"
            UserDefaults.standard.set(n, forKey: "nou.depin.nodeID"); return n
        }()
        let apiKey = UserDefaults.standard.string(forKey: "nou.depin.apiKey") ?? {
            let k = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            UserDefaults.standard.set(k, forKey: "nou.depin.apiKey"); return k
        }()
        let ram = ProcessInfo.processInfo.physicalMemory / (1024*1024*1024)
        guard let url = URL(string: "https://chatweb.ai/api/v1/nodes/register"),
              let body = try? JSONSerialization.data(withJSONObject: [
                "node_id": nodeID, "api_key": apiKey, "tunnel_url": tunnelURL,
                "ram_gb": ram, "models": ["main","fast","vision"], "version": "1.0.0"
              ]) else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"; req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: req) { [weak self] _, resp, _ in
            Task { @MainActor in
                guard let self else { return }
                self.tunnelURL = tunnelURL; self.refreshStatus()
                self.showAlert(
                    L("🌍 DePIN起動！","🌍 DePIN Active!"),
                    "URL: \(tunnelURL)\n\nANTHROPIC_BASE_URL=\(tunnelURL)\nANTHROPIC_API_KEY=sk-ant-dummy"
                )
            }
        }.resume()
    }

    @objc func stopDepin() {
        depinActive = false; allowSleep(); tunnelURL = nil
        Task {
            await RelayClient.shared.disconnect()
            await MainActor.run { self.refreshStatus() }
        }
    }

    @objc func depinStatus() {
        let nodeID = UserDefaults.standard.string(forKey: "nou.relay.nodeID") ?? "—"
        let running = relayConnected
        let idle = Self.getIdleSeconds()
        let turl = relayPublicURL ?? "none"
        showAlert("DePIN (NOU Relay)", """
        \(running ? "● Connected (nou.run)" : "○ Disconnected")
        \(running ? (idle >= 300 ? "💰 Idle earning" : "🟢 Active") : "")
        Node ID: \(nodeID)
        URL: \(turl)
        Idle: \(Int(idle))s
        """)
    }

    @objc func copyDepinInfo() {
        guard let turl = relayPublicURL, !turl.isEmpty else {
            showAlert(L("Relayなし","No Relay"), L("接続中にリトライします...","Connecting... try again shortly")); return
        }
        let nodeID = UserDefaults.standard.string(forKey: "nou.relay.nodeID") ?? "unknown"
        let info = "Node ID: \(nodeID)\nURL: \(turl)\n\nexport ANTHROPIC_BASE_URL=\(turl)\nexport ANTHROPIC_API_KEY=sk-ant-dummy\nclaude --dangerously-skip-permissions"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info, forType: .string)
        showAlert(L("コピーしました","Copied!"), turl)
    }

    // MARK: - Actions: Connect

    @objc func toggleAutoTunnel() {
        // Relay is always on — show current state
        let connected = relayConnected
        let msg = connected
            ? (relayPublicURL ?? L("接続中...","Connecting..."))
            : L("未接続 — 再接続中...","Disconnected — reconnecting...")
        showAlert(L("🌐 NOU Relay","🌐 NOU Relay"), msg)
    }

    @objc func startTunnel() {
        let tm = TunnelManager.shared
        // Relay is managed automatically — just show current state
        if relayConnected, let url = relayPublicURL {
            showAlert(L("🌐 Relay実行中","🌐 Relay Running"), url)
            return
        }
        Task {
            await RelayClient.shared.connect()
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let snap = await RelayClient.shared.snapshot
                if let u = snap["public_url"] as? String, !u.isEmpty {
                    await MainActor.run {
                        self.relayPublicURL = u
                        self.relayConnected = true
                        self.refreshStatus()
                        self.showAlert(L("🌐 Relay起動！","🌐 Relay Active!"), u)
                    }
                    return
                }
            }
        }
    }

    @objc func stopTunnel() {
        Task {
            await RelayClient.shared.disconnect()
            await MainActor.run {
                self.relayConnected = false
                self.relayPublicURL = nil
                self.tunnelURL = nil
                self.refreshStatus()
            }
        }
    }

    @objc func copyRemoteURL() {
        guard let url = relayPublicURL, !url.isEmpty else {
            showAlert(L("Relayなし","No Relay"), L("接続中...しばらくお待ちください","Connecting... please wait")); return
        }
        let key = getAPIKey()
        let info = "export ANTHROPIC_BASE_URL=\(url)\nexport ANTHROPIC_API_KEY=\(key)\nclaude --dangerously-skip-permissions"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info, forType: .string)
        showAlert(L("コピーしました！","Copied!"), url)
    }

    @objc func copyURL() {
        let ip = getLANIP(); let key = getAPIKey()
        let info = "export ANTHROPIC_BASE_URL=http://\(ip):4001\nexport ANTHROPIC_API_KEY=\(key)\nclaude --dangerously-skip-permissions"
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(info, forType: .string)
        showAlert(L("LAN URLをコピー","LAN URL Copied"), "http://\(ip):4001")
    }

    @objc func openProxySettings() {
        // Open macOS Network preferences (proxy settings)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.network") {
            NSWorkspace.shared.open(url)
        }
        // Also copy PAC URL to clipboard for convenience
        let pacURL = "http://localhost:4001/proxy.pac"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pacURL, forType: .string)
        showAlert(
            L("Auto-Proxy設定", "Auto-Proxy Setup"),
            L("PAC URLをクリップボードにコピーしました。\nネットワーク設定で「自動プロキシ構成」にペーストしてください。\n\n\(pacURL)",
              "PAC URL copied to clipboard.\nPaste it into \"Automatic Proxy Configuration\" in Network settings.\n\n\(pacURL)")
        )
    }

    // MARK: - Actions: More

    @objc func runBench() {
        showAlert(L("ベンチマーク実行中...","Benchmarking..."), "~30s")
        let aiSh = NSHomeDirectory() + "/ai.sh"
        if FileManager.default.fileExists(atPath: aiSh) {
            runShell("'\(aiSh)' bench") { [weak self] out in
                self?.showAlert(L("結果","Results"), out.isEmpty ? "Done." : out)
            }
        } else {
            // ダッシュボードのベンチマークページを開く
            NSWorkspace.shared.open(URL(string: "http://localhost:4001/#bench")!)
        }
    }

    @objc func openLogs() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("nou.log"))
    }

    @objc func openGenerated() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("generated")
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: dir.path) ? dir
            : FileManager.default.homeDirectoryForCurrentUser)
    }

    @objc func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/yukihamada/nou")!)
    }

    @objc func openNativeSettings() {
        NOUSettingsWindowController.shared.showSettings()
    }

    @objc func pauseNOU() {
        let alert = NSAlert()
        alert.messageText = "NOU を休止しますか？"
        alert.informativeText = "AI サーバーを停止します。メニューバーのアイコンは残りますが、チャットやAPI は使えなくなります。再開するには右クリック→設定から。"
        alert.addButton(withTitle: "休止する")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn {
            // Stop proxy server, relay, etc. but keep app alive
            NotificationCenter.default.post(name: Notification.Name("NOU.pause"), object: nil)
            statusItem.button?.title = "⏸"
        }
    }

    @objc func uninstallNOU() {
        let alert = NSAlert()
        alert.messageText = "NOU をアンインストールしますか？"
        alert.informativeText = "NOU.app を削除し、ログイン時の自動起動を解除します。\n\nモデルデータ (~/.ollama/) は残りますので、必要に応じて手動で削除してください。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "アンインストール")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn {
            // 1. Remove login item
            if #available(macOS 13.0, *) {
                try? SMAppService.mainApp.unregister()
            }
            // 2. Remove NOU config
            let fm = FileManager.default
            let nouDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".nou")
            try? fm.removeItem(at: nouDir)
            // 3. Move app to trash
            let appURL = Bundle.main.bundleURL
            NSWorkspace.shared.recycle([appURL]) { _, error in
                if let error {
                    print("[NOU] Uninstall error: \(error)")
                }
            }
            // 4. Quit
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApp.terminate(nil)
            }
        }
    }

    @objc func quit() { allowSleep(); NSApp.terminate(nil) }
}
