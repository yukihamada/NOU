import Foundation
import Hummingbird

/// Custom Hummingbird request context that captures the TCP peer address at connection time.
/// This value cannot be spoofed via HTTP headers — it comes directly from the NIO channel.
struct NOURequestContext: RequestContext {
    var coreContext: CoreRequestContextStorage
    /// Raw TCP peer IP address (v4/v6). Nil for unix domain sockets.
    let tcpRemoteIP: String?

    init(source: Source) {
        self.coreContext = .init(source: source)
        self.tcpRemoteIP = source.channel.remoteAddress?.ipAddress
    }
}
