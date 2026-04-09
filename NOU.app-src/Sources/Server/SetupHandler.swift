import Foundation
import Hummingbird
import AppKit

enum SetupHandler {

    // MARK: - Claude Code

    static func handleClaudeCode(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }

        let port = ModelRegistry.proxyPort
        let baseURL = "http://localhost:\(port)"
        let skipPerms = UserDefaults.standard.bool(forKey: "nou.claudecode.skipDangerousPerms")
        let skipFlag = skipPerms ? " --dangerously-skip-permissions" : ""

        // デフォルトフォルダが設定されていれば使用、なければ選択ダイアログ
        let savedFolder = UserDefaults.standard.string(forKey: "nou.tool.claudecode.folder")
        let folder: String?
        if let saved = savedFolder, !saved.isEmpty {
            folder = saved
        } else {
            folder = await pickFolder(title: "Claude Code を起動するフォルダを選択")
        }

        let cdPart = folder.map { "cd \"\($0)\" && " } ?? ""
        launchInTerminal("\(cdPart)ANTHROPIC_BASE_URL=\(baseURL) ANTHROPIC_API_KEY=sk-nou claude\(skipFlag)")

        let dir = folder ?? "カレントディレクトリ"
        return jsonResponse(["ok": true, "message": "Claude Code を起動しました (\(dir))"])
    }

    // MARK: - Aider

    static func handleAider(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }

        let port = ModelRegistry.proxyPort
        let aiderModel = UserDefaults.standard.string(forKey: "nou.aider.model") ?? "openai/auto"

        let savedFolder = UserDefaults.standard.string(forKey: "nou.tool.aider.folder")
        let folder: String?
        if let saved = savedFolder, !saved.isEmpty {
            folder = saved
        } else {
            folder = await pickFolder(title: "Aider を起動するフォルダを選択")
        }

        let cdPart = folder.map { "cd \"\($0)\" && " } ?? ""
        launchInTerminal("\(cdPart)OPENAI_API_BASE=http://localhost:\(port)/v1 OPENAI_API_KEY=sk-nou aider --model \(aiderModel)")

        let dir = folder ?? "カレントディレクトリ"
        return jsonResponse(["ok": true, "message": "Aider を起動しました (\(dir))"])
    }

    // MARK: - Cursor

    static func handleCursor(request: Request, context: some RequestContext) async throws -> Response {
        if let deny = AuthCheck.requireLocal(request: request) { return deny }

        let port = ModelRegistry.proxyPort
        let cursorDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User")
        let settingsPath = cursorDir.appendingPathComponent("settings.json")
        var written: [String] = []
        var skipped: [String] = []

        do {
            try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
            var settings: [String: Any] = [:]
            if let data = try? Data(contentsOf: settingsPath),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existing
            }
            var changed = false
            if settings["openai.apiBaseUrl"] == nil {
                settings["openai.apiBaseUrl"] = "http://localhost:\(port)/v1"
                changed = true
            } else { skipped.append("openai.apiBaseUrl (既存の値を保持)") }

            if changed {
                let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: settingsPath)
                written.append("Cursor/User/settings.json")
            }
        } catch { skipped.append("settings.json: \(error.localizedDescription)") }

        // Cursor を起動（デフォルトフォルダがあればそこで開く）
        let cursorFolder = UserDefaults.standard.string(forKey: "nou.tool.cursor.folder") ?? ""
        let launched = launchApp("Cursor")
        if !launched {
            let cdPart = cursorFolder.isEmpty ? "" : "cd \"\(cursorFolder)\" && "
            launchInTerminal("\(cdPart)cursor .")
        } else if !cursorFolder.isEmpty {
            // open でフォルダを Cursor に渡す
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", "Cursor", cursorFolder]
            try? p.run()
        }

        let msg = written.isEmpty
            ? "設定済みです（既存の設定を保持）。Cursor を起動しました。"
            : "設定完了！Cursor を起動しました（再起動で有効になります）。"
        return jsonResponse(["ok": true, "written": written, "skipped": skipped, "message": msg])
    }

    // MARK: - Folder picker

    /// Shows NSOpenPanel on the main thread and returns the selected path (or nil if cancelled).
    @MainActor
    private static func pickFolderOnMain(title: String) -> String? {
        // LSUIElement アプリでパネルを前面に出すため一時的に regular モードへ
        let prev = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "このフォルダで起動"
        // QuickAI パネルより上に確実に表示
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        panel.orderFrontRegardless()
        panel.makeKey()

        let result = panel.runModal() == .OK ? panel.url?.path : nil

        // 元のモードに戻す（Dockからアイコンを消す）
        NSApp.setActivationPolicy(prev)
        return result
    }

    private static func pickFolder(title: String) async -> String? {
        await MainActor.run { pickFolderOnMain(title: title) }
    }

    // MARK: - Launch helpers

    @discardableResult
    private static func launchApp(_ appName: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]
        do { try process.run(); return true } catch { return false }
    }

    static let terminalKey = "nou.preferred.terminal"

    static var availableTerminals: [(id: String, name: String, bundleId: String)] {
        [
            ("terminal",  "Terminal",   "com.apple.Terminal"),
            ("iterm2",    "iTerm2",     "com.googlecode.iterm2"),
            ("warp",      "Warp",       "dev.warp.Warp-Stable"),
            ("alacritty", "Alacritty",  "org.alacritty"),
            ("kitty",     "kitty",      "net.kovidgoyal.kitty"),
            ("wezterm",   "WezTerm",    "com.github.wez.wezterm"),
            ("ghostty",   "Ghostty",    "com.mitchellh.ghostty"),
        ]
    }

    /// Returns list of installed terminals
    static var installedTerminals: [(id: String, name: String)] {
        availableTerminals.compactMap { t in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.bundleId) != nil
                ? (t.id, t.name) : nil
        }
    }

    /// Preferred terminal ID stored in UserDefaults (defaults to first installed)
    static var preferredTerminalId: String {
        get { UserDefaults.standard.string(forKey: terminalKey) ?? installedTerminals.first?.id ?? "terminal" }
        set { UserDefaults.standard.set(newValue, forKey: terminalKey) }
    }

    private static func launchInTerminal(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\"", with: "\\\"")
        let termId = preferredTerminalId

        switch termId {
        case "iterm2":
            let script = """
            tell application "iTerm2"
                create window with default profile command "\(escaped)"
            end tell
            """
            if runAppleScript(script) { return }
        case "warp":
            // Warp: open with env via shell
            let script = """
            tell application "Warp" to activate
            delay 0.3
            tell application "System Events" to tell process "Warp"
                keystroke "t" using command down
            end tell
            delay 0.2
            tell application "System Events"
                keystroke "\(escaped)"
                key code 36
            end tell
            """
            if runAppleScript(script) { return }
        case "alacritty":
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Alacritty", "--args", "-e", "sh", "-c", command]
            try? process.run()
            return
        case "kitty", "wezterm", "ghostty":
            // These support --command or -e flags
            let appName = availableTerminals.first(where: { $0.id == termId })?.name ?? termId
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appName, "--args", "-e", "sh", "-c", command]
            try? process.run()
            return
        default: break
        }

        // Default: Terminal.app
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        _ = runAppleScript(script)
    }

    @discardableResult
    private static func runAppleScript(_ src: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", src]
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }

    // MARK: - One-click setup API

    /// GET /api/setup/status — check install/download/server state
    static func handleStatus(request: Request, context: some RequestContext) async throws -> Response {
        let mlxlmInstalled = isMLXLMInstalled()
        let fastAlive = await HealthHandler.isAlive(port: ModelRegistry.portFast)
        let mainAlive = await HealthHandler.isAlive(port: ModelRegistry.portMain)
        let serverRunning = fastAlive || mainAlive
        let recPreset = OnboardingHandler.recommend(ramGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824))

        let ggufPath = findExistingGGUF()
        let lcppAlive = await HealthHandler.isAlive(port: ModelRegistry.llamacppPortFast)

        let result: [String: Any] = [
            "mlxlm_installed":   mlxlmInstalled,
            "server_running":    serverRunning,
            "gguf_model":        ggufPath as Any,
            "llamacpp_running":  lcppAlive,
            "recommendation": [
                "preset_id":    recPreset.presetID,
                "display_name": recPreset.displayName,
                "mlx_model_id": recPreset.mlxModelID,
                "ram_gb":       recPreset.ramGB,
                "reason":       recPreset.reason,
            ] as [String: Any]
        ]
        return jsonResponse(result)
    }

    /// POST /api/setup/install-mlxlm — SSE stream: pip3 install mlx-lm from GitHub
    static func handleInstallMLXLM(request: Request, context: some RequestContext) async throws -> Response {
        let pip = findPip()
        let args = [pip, "install", "--upgrade", "git+https://github.com/ml-explore/mlx-lm.git"]
        let body = ResponseBody { writer in
            for await line in runCommandLines(args) {
                let safe = line.replacingOccurrences(of: "\"", with: "'")
                try? await writer.write(ByteBuffer(string: "data: {\"line\":\"\(safe)\"}\n\n"))
            }
            let installed = isMLXLMInstalled()
            try? await writer.write(ByteBuffer(string: "data: {\"done\":true,\"ok\":\(installed)}\n\n"))
            try? await writer.finish(nil)
        }
        return Response(status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: body)
    }

    /// POST /api/setup/download-model  body: { "model_id": "mlx-community/..." }
    static func handleDownloadModel(request: Request, context: some RequestContext) async throws -> Response {
        let buf = try await request.body.collect(upTo: 4096)
        let bodyDict = (try? JSONSerialization.jsonObject(with: buf.getData(at: 0, length: buf.readableBytes) ?? Data())) as? [String: Any]
        let modelID = bodyDict?["model_id"] as? String ?? ""
        guard !modelID.isEmpty else {
            return jsonResponse(["error": "missing model_id"])
        }
        let mlxlm = findMLXLM()
        let args = [mlxlm, "manage", "--download", modelID]
        let safeModelID = modelID.replacingOccurrences(of: "\"", with: "'")
        let body = ResponseBody { writer in
            for await line in runCommandLines(args) {
                let safe = line.replacingOccurrences(of: "\"", with: "'")
                try? await writer.write(ByteBuffer(string: "data: {\"line\":\"\(safe)\"}\n\n"))
            }
            try? await writer.write(ByteBuffer(string: "data: {\"done\":true,\"ok\":true,\"model_id\":\"\(safeModelID)\"}\n\n"))
            try? await writer.finish(nil)
        }
        return Response(status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: body)
    }

    // MARK: - Ollama install/pull

    /// POST /api/setup/install-ollama — SSE stream: brew install ollama
    static func handleInstallOllama(request: Request, context: some RequestContext) async throws -> Response {
        let brew = "/opt/homebrew/bin/brew"
        let body = ResponseBody { writer in
            func send(_ d: [String: Any]) async {
                if let data = try? JSONSerialization.data(withJSONObject: d),
                   let s = String(data: data, encoding: .utf8) {
                    try? await writer.write(ByteBuffer(string: "data: \(s)\n\n"))
                }
            }

            let ollamaPath = "/opt/homebrew/bin/ollama"
            if FileManager.default.fileExists(atPath: ollamaPath) {
                await send(["done": true, "ok": true, "message": "Ollama はすでにインストールされています"])
                try? await writer.finish(nil)
                return
            }

            guard FileManager.default.isExecutableFile(atPath: brew) else {
                await send(["error": "Homebrew が見つかりません。https://brew.sh でインストール後、再試行してください。",
                            "action": "open_url", "url": "https://brew.sh"])
                try? await writer.finish(nil)
                return
            }

            await send(["line": "brew install ollama を実行中..."])
            for await line in runCommandLines([brew, "install", "ollama"]) {
                let safe = line.replacingOccurrences(of: "\"", with: "'")
                await send(["line": safe])
            }
            let installed = FileManager.default.fileExists(atPath: ollamaPath)
            await send(["done": true, "ok": installed,
                        "message": installed ? "Ollama のインストールが完了しました！" : "インストールに失敗しました"])
            try? await writer.finish(nil)
        }
        return Response(status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: body)
    }

    /// POST /api/setup/pull-ollama-model  body: { "model": "qwen3.5:14b" }
    static func handlePullOllamaModel(request: Request, context: some RequestContext) async throws -> Response {
        let buf = try await request.body.collect(upTo: 4096)
        let bodyDict = (try? JSONSerialization.jsonObject(with: buf.getData(at: 0, length: buf.readableBytes) ?? Data())) as? [String: Any]
        let model = bodyDict?["model"] as? String ?? "qwen3.5:14b"

        let ollamaPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama")
            ? "/opt/homebrew/bin/ollama" : "/usr/local/bin/ollama"
        guard FileManager.default.isExecutableFile(atPath: ollamaPath) else {
            let err = try? JSONSerialization.data(withJSONObject: ["error": "Ollama が見つかりません"])
            return Response(status: .ok, headers: [.contentType: "application/json"],
                            body: .init(byteBuffer: .init(data: err ?? Data())))
        }

        let safeModel = model.replacingOccurrences(of: "\"", with: "")
        let streamBody = ResponseBody { writer in
            func send(_ d: [String: Any]) async {
                if let data = try? JSONSerialization.data(withJSONObject: d),
                   let s = String(data: data, encoding: .utf8) {
                    try? await writer.write(ByteBuffer(string: "data: \(s)\n\n"))
                }
            }
            await send(["line": "ollama pull \(safeModel) を実行中..."])
            for await line in runCommandLines([ollamaPath, "pull", safeModel]) {
                let safe = line.replacingOccurrences(of: "\"", with: "'")
                await send(["line": safe])
            }
            await send(["done": true, "ok": true, "model": safeModel])
            try? await writer.finish(nil)
        }
        return Response(status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: streamBody)
    }

    /// POST /api/setup/start-mlx-server  body: { "model_id": "...", "port": 5001 }
    static func handleStartMLXServer(request: Request, context: some RequestContext) async throws -> Response {
        let buf = try await request.body.collect(upTo: 4096)
        let bodyDict = (try? JSONSerialization.jsonObject(with: buf.getData(at: 0, length: buf.readableBytes) ?? Data())) as? [String: Any]
        let modelID = bodyDict?["model_id"] as? String ?? ModelRegistry.activePreset(slot: "fast").mlxModelID
        let port = bodyDict?["port"] as? Int ?? ModelRegistry.portFast

        // Already running?
        let alive = await HealthHandler.isAlive(port: port)
        if alive {
            return jsonResponse(["ok": true, "message": "already running", "port": port])
        }

        let mlxlm = findMLXLM()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: mlxlm)
        p.arguments = ["server", "--model", modelID, "--port", "\(port)"]

        // Detach — let it run independently
        let logDir = (FileManager.default.homeDirectoryForCurrentUser.path) + "/Library/Logs/NOU"
        try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
        let logPath = logDir + "/mlx-server-\(port).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        if let fh = FileHandle(forWritingAtPath: logPath) {
            p.standardOutput = fh; p.standardError = fh
        }

        do {
            try p.run()
            return jsonResponse(["ok": true, "message": "server starting", "port": port, "model": modelID, "pid": p.processIdentifier])
        } catch {
            return jsonResponse(["ok": false, "error": error.localizedDescription])
        }
    }

    // MARK: - Private helpers

    private static func isMLXLMInstalled() -> Bool {
        let mlxlm = findMLXLM()
        return FileManager.default.isExecutableFile(atPath: mlxlm)
    }

    private static func findPip() -> String {
        let candidates = ["/opt/homebrew/bin/pip3", "/usr/local/bin/pip3", "/usr/bin/pip3"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "pip3"
    }

    private static func findMLXLM() -> String {
        let candidates = [
            "/opt/homebrew/bin/mlx_lm",
            "/usr/local/bin/mlx_lm",
            "\(NSHomeDirectory())/.local/bin/mlx_lm",
            "\(NSHomeDirectory())/Library/Python/3.11/bin/mlx_lm",
            "\(NSHomeDirectory())/Library/Python/3.12/bin/mlx_lm",
            "\(NSHomeDirectory())/Library/Python/3.13/bin/mlx_lm",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/mlx_lm",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/mlx_lm",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/mlx_lm",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "mlx_lm"
    }

    /// Run a command and yield each output line via AsyncStream.
    private static func runCommandLines(_ args: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            guard let exe = args.first, FileManager.default.isExecutableFile(atPath: exe) else {
                continuation.yield("Error: command not found — \(args.first ?? "")")
                continuation.finish()
                return
            }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = Array(args.dropFirst())

            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError  = pipe
            let handle = pipe.fileHandleForReading

            var buf = Data()
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                guard !chunk.isEmpty else { return }
                buf.append(chunk)
                while let nl = buf.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = buf[buf.startIndex..<nl]
                    if let line = String(data: lineData, encoding: .utf8), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                        continuation.yield(line)
                    }
                    buf = buf[buf.index(after: nl)...]
                }
            }
            p.terminationHandler = { _ in
                handle.readabilityHandler = nil
                // Flush remaining buffer
                if !buf.isEmpty, let line = String(data: buf, encoding: .utf8), !line.isEmpty {
                    continuation.yield(line)
                }
                continuation.finish()
            }

            do { try p.run() }
            catch {
                continuation.yield("Failed to start: \(error.localizedDescription)")
                continuation.finish()
            }
        }
    }

    // MARK: - GGUF download for llama.cpp benchmark

    static let ggufDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".nou/gguf")
    static let ggufModelURL = "https://huggingface.co/lmstudio-community/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf"
    static let ggufModelName = "gemma-3-1b-it-Q4_K_M.gguf"

    static var ggufModelPath: URL { ggufDir.appendingPathComponent(ggufModelName) }

    /// 既存のGGUFモデルを検索（ダウンロード不要）
    static func findExistingGGUF() -> String? {
        let candidates = [
            // NOU bundled model (extracted on first launch)
            "\(NSHomeDirectory())/Library/Application Support/NOU/models/Qwen3-1.7B-Q4_K_M.gguf",
            "\(NSHomeDirectory())/Library/Application Support/Koe/llm-models/Qwen3-1.7B-Q4_K_M.gguf",
            "\(NSHomeDirectory())/Library/Application Support/Jan/data/models/imported/jan-nano-4b-iQ4_XS.gguf",
            "\(NSHomeDirectory())/Library/Application Support/Jan/data/models/huggingface.co/Menlo/Jan-nano-128k-gguf/jan-nano-128k-iQ4_XS.gguf",
            "\(NSHomeDirectory())/Library/Mobile Documents/com~apple~CloudDocs/Downloads/qwen3-1.7b-q4_0.gguf",
            ggufModelPath.path,
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func isGGUFReady() -> Bool {
        findExistingGGUF() != nil
    }

    /// POST /api/setup/start-llamacpp — start llama-server with existing GGUF on port 5021
    static func handleStartLlamaCpp(request: Request, context: some RequestContext) async throws -> Response {
        guard let ggufPath = findExistingGGUF() else {
            return jsonResponse(["ok": false, "error": "GGUFモデルが見つかりません"])
        }
        // Already running?
        if await HealthHandler.isAlive(port: ModelRegistry.llamacppPortFast) {
            return jsonResponse(["ok": true, "message": "既に起動中です", "model": ggufPath])
        }
        let port = ModelRegistry.llamacppPortFast
        let llamaServer = "/opt/homebrew/bin/llama-server"
        guard FileManager.default.fileExists(atPath: llamaServer) else {
            return jsonResponse(["ok": false, "error": "llama-server が見つかりません (brew install llama.cpp)"])
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: llamaServer)
        p.arguments = [
            "-m", ggufPath,
            "--port", "\(port)",
            "-ngl", "99",       // GPU layers
            "--ctx-size", "4096",
            "--no-warmup",
            "-t", "4",
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        do {
            try p.run()
            // Wait up to 15s for server to start
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if await HealthHandler.isAlive(port: port) {
                    let modelName = URL(fileURLWithPath: ggufPath).lastPathComponent
                    return jsonResponse(["ok": true, "message": "llama-server 起動完了", "model": modelName, "port": port])
                }
            }
            return jsonResponse(["ok": false, "error": "起動タイムアウト (15秒)"])
        } catch {
            return jsonResponse(["ok": false, "error": error.localizedDescription])
        }
    }

    /// POST /api/setup/download-gguf — SSE stream download of a small GGUF for benchmarking
    static func handleDownloadGGUF(request: Request, context: some RequestContext) async throws -> Response {
        // Check disk space (need at least 2GB)
        let freeGB = MetricsHandler.getDiskFreeGB()
        if freeGB < 2.0 {
            let err = try JSONSerialization.data(withJSONObject: ["error": "ディスク空き容量不足 (\(String(format:"%.1f",freeGB))GB). 2GB以上必要です"])
            return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: .init(data: err)))
        }

        if isGGUFReady() {
            let r = try JSONSerialization.data(withJSONObject: ["done": true, "progress": 100, "message": "既にダウンロード済みです"])
            return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: .init(data: r)))
        }

        try? FileManager.default.createDirectory(at: ggufDir, withIntermediateDirectories: true)

        let body = ResponseBody { writer in
            func send(_ dict: [String: Any]) async {
                if let d = try? JSONSerialization.data(withJSONObject: dict),
                   let s = String(data: d, encoding: .utf8) {
                    try? await writer.write(ByteBuffer(string: "data: \(s)\n\n"))
                }
            }

            await send(["progress": 0, "message": "ダウンロード開始..."])

            let destPath = ggufModelPath.path + ".tmp"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = ["-L", "--progress-bar", "-o", destPath, ggufModelURL]

            let pipe = Pipe()
            process.standardError = pipe

            do {
                try process.run()
                // Poll progress via file size
                let expectedBytes: Int64 = 1_600_000_000
                while process.isRunning {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let size = (try? FileManager.default.attributesOfItem(atPath: destPath)[.size] as? Int64) ?? 0
                    let pct = min(99, Int(Double(size) / Double(expectedBytes) * 100))
                    await send(["progress": pct, "message": "\(pct)% (\(size/1_048_576)MB / \(expectedBytes/1_048_576)MB)"])
                }
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    try? FileManager.default.moveItem(atPath: destPath, toPath: ggufModelPath.path)
                    await send(["done": true, "progress": 100, "message": "ダウンロード完了"])
                } else {
                    try? FileManager.default.removeItem(atPath: destPath)
                    await send(["error": "ダウンロード失敗 (code \(process.terminationStatus))"])
                }
            } catch {
                await send(["error": error.localizedDescription])
            }
            try? await writer.finish(nil)
        }

        return Response(status: .ok,
            headers: [.contentType: "text/event-stream", .cacheControl: "no-cache"],
            body: body)
    }

    /// POST /api/setup/delete-model — delete MLX or GGUF model files
    static func handleDeleteModel(request: Request, context: some RequestContext) async throws -> Response {
        let buf = try await request.body.collect(upTo: 4096)
        let body = (try? JSONSerialization.jsonObject(with: buf.getData(at: 0, length: buf.readableBytes) ?? Data())) as? [String: Any]
        let backend = body?["backend"] as? String ?? ""

        var deleted = false
        var message = ""

        switch backend {
        case "llamacpp", "gguf":
            if FileManager.default.fileExists(atPath: ggufModelPath.path) {
                try? FileManager.default.removeItem(at: ggufModelPath)
                deleted = true
                message = "GGUFモデルを削除しました"
            }
        case "mlx":
            // MLX models are in HuggingFace cache
            let cacheDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache/huggingface/hub")
            let mgr = FileManager.default
            var totalDeleted = 0
            if let dirs = try? mgr.contentsOfDirectory(atPath: cacheDir.path) {
                for d in dirs where d.contains("mlx") {
                    let full = cacheDir.appendingPathComponent(d)
                    if let size = (try? mgr.attributesOfItem(atPath: full.path)[.size] as? Int64) {
                        totalDeleted += Int(size)
                    }
                    try? mgr.removeItem(at: full)
                    deleted = true
                }
            }
            message = deleted ? "MLXモデルを削除しました (\(totalDeleted/1_048_576)MB)" : "削除対象なし"
        default:
            message = "不明なバックエンド"
        }

        return jsonResponse(["ok": deleted, "message": message])
    }

    // MARK: - Helper

    private static func jsonResponse(_ dict: [String: Any]) -> Response {
        let data = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return Response(status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: data)))
    }
}
