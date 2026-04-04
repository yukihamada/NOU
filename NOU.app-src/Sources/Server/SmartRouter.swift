import Foundation

enum SmartRouter {
    enum Complexity: String {
        case simple   // fast slot (small model, fast response)
        case medium   // main slot (standard model)
        case complex  // main slot with higher max_tokens
    }

    private static let complexKeywords = [
        "analyze", "review", "explain", "implement", "refactor",
        "debug", "compare", "evaluate", "design", "architect",
        "optimize", "summarize", "translate",
        // Japanese
        "分析", "レビュー", "実装", "リファクタ", "デバッグ",
        "比較", "評価", "設計", "最適化", "要約", "翻訳", "説明",
    ]

    static func classify(messages: [[String: Any]]) -> Complexity {
        let lastUserMsg = messages.last(where: { $0["role"] as? String == "user" })
        let content = lastUserMsg?["content"] as? String ?? ""
        let totalContent = messages.compactMap { $0["content"] as? String }.joined()

        let tokenEstimate = totalContent.count / 4
        let messageCount = messages.count

        // Simple: short prompt, single turn
        if tokenEstimate < 50 && messageCount <= 2 {
            return .simple
        }

        // Complex: long context, multi-turn, or analysis keywords
        let lower = content.lowercased()
        let hasComplexKeyword = complexKeywords.contains(where: { lower.contains($0) })

        if tokenEstimate > 500 || messageCount > 6 || hasComplexKeyword {
            return .complex
        }

        return .medium
    }

    static func slot(for complexity: Complexity) -> String {
        switch complexity {
        case .simple: return "fast"
        case .medium, .complex: return "main"
        }
    }

    static let smartModelNames: Set<String> = ["auto", "nou", "smart", "nou-auto"]
    static let agentModelNames: Set<String> = ["nou-agent", "agent"]

    static func isSmart(_ model: String) -> Bool {
        smartModelNames.contains(model.lowercased())
    }

    static func isAgent(_ model: String) -> Bool {
        agentModelNames.contains(model.lowercased())
    }
}
