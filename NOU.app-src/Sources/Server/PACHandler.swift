import Foundation
import Hummingbird

struct PACHandler {
    static let pacContent = """
    function FindProxyForURL(url, host) {
        // Redirect AI API calls to local NOU proxy
        if (host === "api.openai.com" ||
            host === "api.anthropic.com" ||
            host === "generativelanguage.googleapis.com") {
            return "PROXY 127.0.0.1:4001";
        }
        return "DIRECT";
    }
    """

    static func handle(_ request: Request, _ context: some RequestContext) async throws -> Response {
        return Response(
            status: .ok,
            headers: [.contentType: "application/x-ns-proxy-autoconfig"],
            body: .init(byteBuffer: .init(string: pacContent))
        )
    }
}
