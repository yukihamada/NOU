import Foundation

enum WebSearchPlugin {
    static func execute(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String else {
            return "Error: missing 'query' parameter"
        }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return "Error: invalid query"
        }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let html = String(data: data, encoding: .utf8) else {
                return "Error: could not decode response"
            }
            return parseResults(html: html, maxResults: 5)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private static func parseResults(html: String, maxResults: Int) -> String {
        var results: [String] = []

        let titlePattern = "class=\"result__a\"[^>]*>([^<]+)</a>"
        let snippetPattern = "class=\"result__snippet\"[^>]*>([^<]+)"

        let titles = regexMatches(for: titlePattern, in: html)
        let snippets = regexMatches(for: snippetPattern, in: html)

        for i in 0..<min(maxResults, min(titles.count, snippets.count)) {
            let title = titles[i].trimmingCharacters(in: .whitespacesAndNewlines)
            let snippet = snippets[i]
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            results.append("\(i + 1). \(title)\n   \(snippet)")
        }

        if results.isEmpty {
            // Fallback: try extracting any text content between result divs
            let fallbackPattern = "class=\"result__body\"[^>]*>([^<]{20,})"
            let fallback = regexMatches(for: fallbackPattern, in: html)
            for (i, text) in fallback.prefix(maxResults).enumerated() {
                results.append("\(i + 1). \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        return results.isEmpty ? "No results found for this query." : results.joined(separator: "\n\n")
    }

    private static func regexMatches(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { result in
            result.numberOfRanges > 1 ? nsText.substring(with: result.range(at: 1)) : nil
        }
    }
}
