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
            setupRow(icon: "🦙", title: "Ollama", subtitle: "AIエンジン (自動インストール)", ok: ollamaOK)
            setupRow(icon: "⚡", title: "Ollama サービス起動", subtitle: "バックグラウンドで常駐", ok: ollamaRunning)
            setupRow(icon: "🧠", title: "Qwen3.5 モデル", subtitle: "推奨AIモデル (自動ダウンロード)", ok: modelOK)

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

    // MARK: Fully automatic setup — no user action needed
    private func startAutoSetup() {
        Task {
            // 1. Check & install Ollama
            await updateStatus("Ollama を確認中...", progress: 0.05)
            let ollamaPath = findOllama()
            if let path = ollamaPath {
                await updateStatus("Ollama 検出済み", progress: 0.15)
                await MainActor.run { ollamaOK = true }
            } else {
                await updateStatus("Ollama をインストール中... (brew install ollama)", progress: 0.1)
                let brew = "/opt/homebrew/bin/brew"
                if FileManager.default.fileExists(atPath: brew) {
                    await runProcess(brew, args: ["install", "ollama"])
                } else {
                    // No brew: try direct download from ollama.com
                    await updateStatus("Ollama をダウンロード中 (ollama.com)...", progress: 0.1)
                    // Fallback: open download page. User must install manually.
                    await MainActor.run {
                        NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
                        statusText = "Ollama を手動でインストールしてください"
                    }
                    return
                }
                if findOllama() != nil {
                    await MainActor.run { ollamaOK = true }
                    await updateStatus("Ollama インストール完了", progress: 0.2)
                } else {
                    await updateStatus("Ollama のインストールに失敗しました", progress: 0.2)
                    return
                }
            }

            // 2. Start Ollama service
            await updateStatus("Ollama サービスを起動中...", progress: 0.25)
            let ollamaExe = findOllama()!
            // Start ollama serve if not already running
            let isRunning = await checkOllamaServing()
            if !isRunning {
                // Try brew services first, fallback to direct
                let brew = "/opt/homebrew/bin/brew"
                if FileManager.default.fileExists(atPath: brew) {
                    await runProcess(brew, args: ["services", "start", "ollama"])
                } else {
                    // Direct: run `ollama serve` in background
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: ollamaExe)
                    p.arguments = ["serve"]
                    p.standardOutput = FileHandle.nullDevice
                    p.standardError = FileHandle.nullDevice
                    try? p.run()
                    // Don't waitUntilExit — it runs as daemon
                }
                // Wait for it to come up (max 30s)
                for _ in 0..<30 {
                    if await checkOllamaServing() { break }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            if await checkOllamaServing() {
                await MainActor.run { ollamaRunning = true }
                await updateStatus("Ollama 稼働中", progress: 0.35)
            } else {
                await updateStatus("Ollama の起動に失敗しました", progress: 0.35)
                return
            }

            // 3. Check if any model exists, if not pull recommended
            await updateStatus("モデルを確認中...", progress: 0.4)
            let hasModel = await checkHasModel(ollamaExe)
            if hasModel {
                await MainActor.run { modelOK = true }
                await updateStatus("モデル検出済み", progress: 1.0)
            } else {
                // Determine best model based on RAM
                let ram = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
                let model: String
                if ram >= 32 {
                    model = "qwen3.5:32b"
                } else if ram >= 16 {
                    model = "qwen3.5:14b"
                } else {
                    model = "qwen3.5:4b"
                }
                await updateStatus("\(model) をダウンロード中... (初回のみ・数分かかります)", progress: 0.45)

                // Pull with progress monitoring
                let pullP = Process()
                pullP.executableURL = URL(fileURLWithPath: ollamaExe)
                pullP.arguments = ["pull", model]
                let pullPipe = Pipe()
                pullP.standardOutput = pullPipe
                pullP.standardError = pullPipe
                try? pullP.run()

                // Monitor progress by reading output
                let handle = pullPipe.fileHandleForReading
                handle.readabilityHandler = { fh in
                    let data = fh.availableData
                    guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                    // Ollama pull outputs percentage lines
                    if line.contains("%") {
                        if let pctStr = line.components(separatedBy: " ").first(where: { $0.contains("%") }),
                           let pct = Double(pctStr.replacingOccurrences(of: "%", of: "")) {
                            let mapped = 0.45 + (pct / 100.0) * 0.5  // 45% - 95%
                            Task { @MainActor in
                                progress = mapped
                                statusText = "\(model) をダウンロード中... \(Int(pct))%"
                            }
                        }
                    }
                }
                pullP.waitUntilExit()
                handle.readabilityHandler = nil

                if await checkHasModel(ollamaExe) {
                    await MainActor.run { modelOK = true }
                    await updateStatus("モデルのダウンロード完了！", progress: 1.0)
                } else {
                    await updateStatus("モデルのダウンロードに失敗しました", progress: 0.95)
                    return
                }
            }

            // All done — auto-transition to done screen
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                withAnimation { isAutoSetupDone = true }
            }
        }
    }

    // MARK: Helpers
    private func findOllama() -> String? {
        let paths = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func checkOllamaServing() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:11434/api/version") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }

    private func checkHasModel(_ ollamaPath: String) async -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ollamaPath)
        p.arguments = ["list"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.components(separatedBy: "\n").count > 2
    }

    @discardableResult
    private func runProcess(_ path: String, args: [String]) async -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
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
