import SwiftUI

// MARK: - Main Dashboard View

struct NOUDashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    var browser: NOUBrowser?

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 14) {
                headerSection
                statsCard
                nodesSection
                modelsSection
                if viewModel.tunnelConnected {
                    tunnelCard
                }
            }
            .padding(16)
        }
        .frame(width: 360, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.startRefresh()
            if let browser {
                viewModel.nodes = browser.nodes
            }
        }
        .onDisappear {
            viewModel.stopRefresh()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            Text("🧠")
                .font(.system(size: 24))
            Text("NOU")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            tierBadge
            statusDot
        }
    }

    private var tierBadge: some View {
        let tier = viewModel.localTier
        let mem = viewModel.memoryGB
        return Text("\(tier.icon) \(tier.rawValue) \(mem > 0 ? "\(mem)GB" : "")")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusDot: some View {
        Circle()
            .fill(viewModel.isOnline ? Color.green : Color.red)
            .frame(width: 8, height: 8)
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                // tok/s gauge
                tokGauge
                    .frame(maxWidth: .infinity)

                // Requests
                statColumn(
                    value: "\(viewModel.totalRequests)",
                    label: "Requests"
                )
                .frame(maxWidth: .infinity)

                // Uptime
                statColumn(
                    value: viewModel.uptimeFormatted,
                    label: "Uptime"
                )
                .frame(maxWidth: .infinity)
            }

            // Tokens bar
            if viewModel.totalTokensOut > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(formatNumber(viewModel.totalTokensOut)) tokens generated")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.depinRequests > 0 {
                        Text("\(viewModel.depinRequests) DePIN")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: 0x58a6ff))
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var tokGauge: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: min(viewModel.tokPerSec / 100, 1.0))
                    .stroke(
                        Color(hex: 0x58a6ff),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: viewModel.tokPerSec)
                Text(String(format: "%.0f", viewModel.tokPerSec))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            Text("tok/s")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Nodes Section

    private var nodesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Nodes")

            // Local node
            localNodeRow

            // Remote nodes
            let remoteNodes = viewModel.nodes.filter { !$0.isLocal }
            ForEach(Array(remoteNodes.enumerated()), id: \.offset) { _, node in
                remoteNodeRow(node)
            }

            if remoteNodes.isEmpty {
                HStack {
                    Image(systemName: "network")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("No remote nodes found")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
            }
        }
    }

    private var localNodeRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isOnline ? Color.green : Color.red)
                .frame(width: 6, height: 6)

            Text(viewModel.hostname)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            // Slot status dots
            ForEach(viewModel.localModels, id: \.name) { slot in
                slotDot(slot)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func remoteNodeRow(_ node: NOUNode) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(node.healthy ? Color.green : Color.red)
                .frame(width: 6, height: 6)

            Text("\(node.tier.icon) \(node.name)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            if node.memoryGB > 0 {
                Text("\(node.memoryGB)GB")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Paired indicator
            Image(systemName: node.paired ? "lock.fill" : "lock.open")
                .font(.system(size: 10))
                .foregroundStyle(node.paired ? Color(hex: 0x58a6ff) : .secondary)

            if node.rpcAvailable {
                Text("RPC")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: 0x58a6ff))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color(hex: 0x58a6ff).opacity(0.15))
                    )
            }

            // Slot status dots
            ForEach(node.models, id: \.name) { slot in
                slotDot(slot)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func slotDot(_ slot: SlotInfo) -> some View {
        let color: Color = slot.running ? .green : Color.white.opacity(0.2)
        return VStack(spacing: 2) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(slot.name.prefix(1).uppercased())
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .help("\(slot.label): \(slot.model) (\(slot.runtime))")
    }

    // MARK: - Models Section

    private var modelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Models")

            if viewModel.localModels.isEmpty {
                Text("No models loaded")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            } else {
                ForEach(viewModel.localModels, id: \.name) { slot in
                    modelCard(slot)
                }
            }
        }
    }

    private func modelCard(_ slot: SlotInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: slotIcon(slot.name))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x58a6ff))

                Text(slot.label.isEmpty ? slot.name : slot.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(slot.runtime == "llamacpp" ? "llama.cpp" : "MLX")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.06)))

                Circle()
                    .fill(slot.running ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
            }

            if !slot.model.isEmpty {
                Text(slot.model)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Tunnel Card

    private var tunnelCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Tunnel")
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x58a6ff))
                if let url = viewModel.tunnelURL {
                    Text(url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x58a6ff))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Connected")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: 0x58a6ff).opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(hex: 0x58a6ff).opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func slotIcon(_ name: String) -> String {
        switch name {
        case "main": return "cpu"
        case "fast": return "bolt"
        case "vision": return "eye"
        default: return "server.rack"
        }
    }

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
