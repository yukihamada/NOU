import AppKit
import SwiftUI

// MARK: - Welcome Window (first-launch onboarding)

@MainActor
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "NOU へようこそ"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1)
        window.center()
        window.setFrameAutosaveName("NOU.Welcome")
        super.init(window: window)
        let view = WelcomeView { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: view)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    override func close() {
        super.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - SwiftUI Welcome View

private struct WelcomeView: View {
    let onDone: () -> Void
    @State private var ollamaOK = false
    @State private var modelOK  = false
    @State private var ollamaRunning = false
    @State private var statusText = "チェック中..."
    @State private var isAutoSetupDone = false
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.07, blue: 0.10).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Divider().background(Color.white.opacity(0.08))
                if isAutoSetupDone {
                    doneView
                } else {
                    autoSetupView
                }
                Spacer()
                footer
            }
        }
        .foregroundColor(.white)
        .onAppear { startAutoSetup() }
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 12) {
            Text("🧠").font(.system(size: 40))
            VStack(alignment: .leading, spacing: 2) {
                Text("NOU へようこそ").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("ワンクリックでローカルAIを使えます")
                    .font(.system(size: 12)).opacity(0.6)
            }
            Spacer()
        }
        .padding(24)
    }

    // MARK: Auto setup view (single screen, no steps needed)
    private var autoSetupView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Overall progress
            VStack(alignment: .leading, spacing: 6) {
                Text("自動セットアップ中...").font(.system(size: 14, weight: .semibold)).opacity(0.7)
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .animation(.easeInOut, value: progress)
                Text(statusText)
                    .font(.system(size: 11)).opacity(0.5)
                    .animation(.easeInOut, value: statusText)
            }

            // Step indicators
            setupRow(icon: "⚡", title: "MLX エンジン", subtitle: "Apple Silicon 専用 AI エンジン", ok: ollamaOK)
            setupRow(icon: "📦", title: "AI モデル", subtitle: "RAM に合ったモデルを自動選択・DL", ok: ollamaRunning)
            setupRow(icon: "🧠", title: "AI サーバー起動", subtitle: "ローカルで推論を実行", ok: modelOK)

            card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("💡 初回は数分かかります。このまま待つだけでOK。").font(.system(size: 11)).opacity(0.6)
                    Text("Wi-Fi でモデルを自動ダウンロードしています。").font(.system(size: 11)).opacity(0.5)
                }
            }
        }
        .padding(24)
    }

    // MARK: Done view
    private var doneView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("✅").font(.system(size: 56))
            Text("準備完了！").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("NOU がメニューバーで動いています。\n🧠 をクリック or ⌃⌥N でチャットを始められます。")
                .font(.system(size: 13)).opacity(0.7)
                .multilineTextAlignment(.center)

            card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("🧠 クリック → クイックチャット", systemImage: "bubble.left").font(.system(size: 12))
                    Label("右クリック → 設定メニュー", systemImage: "gearshape").font(.system(size: 12))
                    Label("⌃⌥N → どこからでもチャット", systemImage: "keyboard").font(.system(size: 12))
                    Label("localhost:4001 → ダッシュボード", systemImage: "rectangle.on.rectangle").font(.system(size: 12))
                }
                .opacity(0.8)
            }

            Button("チャットを始める") {
                NSWorkspace.shared.open(URL(string: "http://localhost:4001")!)
                onDone()
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .padding(24)
    }

    // MARK: Footer
    private var footer: some View {
        HStack {
            if !isAutoSetupDone {
                Button("スキップ") {
                    isAutoSetupDone = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Spacer()
            if isAutoSetupDone {
                Button("閉じる") { onDone() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(20)
    }

    // MARK: Sub-components
    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
    }

    @ViewBuilder
    private func setupRow(icon: String, title: String, subtitle: String, ok: Bool) -> some View {
        card {
            HStack(spacing: 12) {
                Text(icon).font(.system(size: 24)).frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).opacity(0.55)
                }
                Spacer()
                if ok {
                    Label("完了", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    ProgressView().scaleEffect(0.6).opacity(0.5)
                }
            }
        }
    }

    // MARK: Fully automatic setup — MLX primary, Ollama fallback
    private func startAutoSetup() {
        Task {
            let base = "http://127.0.0.1:4001"

            // Wait for proxy server to come up (started by AppDelegate)
            await updateStatus("NOU サーバーの起動を待機中...", progress: 0.02)
            for _ in 0..<15 {
                if await httpOK("\(base)/health") { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            // 1. Check current setup status
            await updateStatus("セットアップ状態を確認中...", progress: 0.05)
            let status = await fetchJSON("\(base)/api/setup/status")
            let mlxInstalled = status?["mlxlm_installed"] as? Bool ?? false
            let serverRunning = status?["server_running"] as? Bool ?? false

            // Determine best MLX model for this Mac's RAM
            let ram = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
            let modelID: String
            let modelName: String
            if ram >= 64 {
                modelID = "mlx-community/Qwen3.5-32B-4bit"; modelName = "Qwen3.5 32B"
            } else if ram >= 24 {
                modelID = "mlx-community/Qwen3.5-14B-4bit"; modelName = "Qwen3.5 14B"
            } else if ram >= 16 {
                modelID = "mlx-community/Qwen3.5-7B-4bit"; modelName = "Qwen3.5 7B"
            } else {
                modelID = "mlx-community/Qwen3.5-4B-4bit"; modelName = "Qwen3.5 4B"
            }

            // 2. Install MLX-LM if needed (uses pip3 bundled with macOS)
            if !mlxInstalled {
                await updateStatus("MLX-LM をインストール中... (Apple Silicon AI エンジン)", progress: 0.1)
                await MainActor.run { ollamaOK = false }
                await callSetupSSE("\(base)/api/setup/install-mlxlm", body: nil) { line in
                    Task { @MainActor in statusText = "MLX-LM: \(line)" }
                }
            }
            await MainActor.run { ollamaOK = true }  // Step 1 done
            await updateStatus("MLX-LM 準備完了", progress: 0.2)

            // 3. Download MLX model
            await updateStatus("\(modelName) をダウンロード中... (初回のみ)", progress: 0.25)
            await MainActor.run { ollamaRunning = false }
            await callSetupSSE("\(base)/api/setup/download-model",
                               body: ["model_id": modelID]) { line in
                // Parse HF download progress if available
                Task { @MainActor in
                    statusText = "\(modelName): \(line)"
                    // Rough progress mapping
                    if line.contains("100%") || line.contains("done") {
                        progress = 0.8
                    } else if progress < 0.75 {
                        progress += 0.005
                    }
                }
            }
            await MainActor.run { ollamaRunning = true }  // Step 2 done
            await updateStatus("\(modelName) ダウンロード完了！", progress: 0.85)

            // 4. Start MLX server
            await updateStatus("AI サーバーを起動中...", progress: 0.9)
            let startBody: [String: Any] = ["model_id": modelID, "port": 5000]
            let _ = await postJSON("\(base)/api/setup/start-mlx-server", body: startBody)

            // Verify server responds
            for _ in 0..<10 {
                if await httpOK("http://127.0.0.1:5000/v1/models") { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            await MainActor.run { modelOK = true }  // Step 3 done
            await updateStatus("準備完了！", progress: 1.0)

            // All done
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                withAnimation { isAutoSetupDone = true }
            }
        }
    }

    // MARK: Networking helpers
    private func httpOK(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        do {
            let (_, r) = try await URLSession.shared.data(from: url)
            return (r as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    private func fetchJSON(_ urlString: String) async -> [String: Any]? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch { return nil }
    }

    private func postJSON(_ urlString: String, body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: urlString),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch { return nil }
    }

    /// Call an SSE endpoint and process each line
    private func callSetupSSE(_ urlString: String, body: [String: Any]?, onLine: @escaping (String) -> Void) async {
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body, let data = try? JSONSerialization.data(withJSONObject: body) {
            req.httpBody = data
        }
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: req)
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let json = String(line.dropFirst(6))
                    if let data = json.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let l = obj["line"] as? String { onLine(l) }
                        if obj["done"] as? Bool == true { break }
                    }
                }
            }
        } catch { onLine("error: \(error.localizedDescription)") }
    }

    private func updateStatus(_ text: String, progress pct: Double) async {
        await MainActor.run {
            statusText = text
            progress = pct
        }
    }
}

// MARK: - Button Styles

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.blue.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundColor(.white)
            .cornerRadius(7)
            .font(.system(size: 12, weight: .semibold))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            .foregroundColor(.white.opacity(0.8))
            .cornerRadius(7)
            .font(.system(size: 12, weight: .medium))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12)))
    }
}
