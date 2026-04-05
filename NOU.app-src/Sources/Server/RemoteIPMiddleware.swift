import Foundation
import HTTPTypes
import Hummingbird

/// Middleware that injects the TCP peer IP as `X-TCP-Remote-IP` into request headers.
/// Because this value comes from the NIO channel (not from client-supplied headers),
/// it cannot be spoofed — even from the local network with a faked Host header.
struct RemoteIPMiddleware: RouterMiddleware, Sendable {
    typealias Context = NOURequestContext

    func handle(
        _ request: Request,
        context: NOURequestContext,
        next: (Request, NOURequestContext) async throws -> Response
    ) async throws -> Response {
        guard let ip = context.tcpRemoteIP else {
            return try await next(request, context)
        }
        var newHead = request.head
        newHead.headerFields[.tcpRemoteIP] = ip
        let newRequest = Request(head: newHead, body: request.body)
        return try await next(newRequest, context)
    }
}

extension HTTPField.Name {
    static let tcpRemoteIP: Self = .init("X-TCP-Remote-IP")!
}
