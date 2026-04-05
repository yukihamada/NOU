import Foundation

/// Tracks DePIN compute rewards earned by this node.
///
/// # Reward Modes
/// - **NCH mode (Japan)**: NOU Compute Hours — barter credit, no cash value.
///   1 NCH = 1 hour of equivalent GPU compute time (normalized to M1 Pro baseline).
///   Legal in Japan as a service barter, not a financial instrument.
/// - **Token mode (Global)**: NOU token on Solana (future settlement).
///   1,000 output tokens processed = 1 CU = 0.001 NOU token.
///
/// Phase 1: off-chain ledger only.
/// Phase 2: weekly Solana batch settlement for non-Japan wallets.
actor RewardLedger {
    static let shared = RewardLedger()
    private init() {
        computeUnits = UserDefaults.standard.integer(forKey: "nou.reward.compute_units")
        walletAddress = UserDefaults.standard.string(forKey: "nou.reward.wallet") ?? ""
        isJapanMode = UserDefaults.standard.bool(forKey: "nou.reward.japan_mode")
    }

    // MARK: - State

    /// Accumulated compute units since first run (1 CU = 1 output token processed externally)
    private(set) var computeUnits: Int = 0

    /// Session compute units (reset on restart)
    private(set) var sessionComputeUnits: Int = 0

    /// Solana wallet address (global mode)
    private(set) var walletAddress: String = ""

    /// Japan mode: use NCH (NOU Compute Hours) — barter credits, no cash value
    private(set) var isJapanMode: Bool = false

    // MARK: - Public API

    func credit(outputTokens: Int) {
        computeUnits += outputTokens
        sessionComputeUnits += outputTokens
        save()
    }

    func setWallet(_ address: String) {
        walletAddress = address
        isJapanMode = false   // setting a Solana wallet means global mode
        save()
    }

    func setJapanMode(_ enabled: Bool) {
        isJapanMode = enabled
        if enabled { walletAddress = "" }
        save()
    }

    func snapshot() -> [String: Any] {
        // NCH: 1 NCH = 3600 CU (1 hour × 3600 tokens/sec baseline)
        let nch = Double(computeUnits) / 3600.0
        // NOU token: 1000 CU = 1 NOU
        let nouTokens = Double(computeUnits) / 1000.0

        return [
            "compute_units": computeUnits,
            "session_compute_units": sessionComputeUnits,
            "wallet_address": walletAddress,
            "is_japan_mode": isJapanMode,
            "nch": nch,                          // NOU Compute Hours (Japan)
            "nou_tokens_estimate": nouTokens,    // NOU token estimate (global)
            "mode": isJapanMode ? "nch" : "token"
        ]
    }

    // MARK: - Persistence

    private func save() {
        UserDefaults.standard.set(computeUnits, forKey: "nou.reward.compute_units")
        UserDefaults.standard.set(walletAddress, forKey: "nou.reward.wallet")
        UserDefaults.standard.set(isJapanMode, forKey: "nou.reward.japan_mode")
    }
}
