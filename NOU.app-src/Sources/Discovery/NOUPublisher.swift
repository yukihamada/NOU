import Foundation

/// Advertises this NOU node on the local network via Bonjour (_nou._tcp).
/// Uses NetService for pure advertisement without binding a port
/// (the HTTP server runs separately on Hummingbird).
final class NOUPublisher: NSObject, NetServiceDelegate {
    private var service: NetService?
    private let port: Int32

    init(port: Int32 = 4001) {
        self.port = port
        super.init()
    }

    func start() {
        let name = Host.current().localizedName ?? "NOU"
        service = NetService(domain: "local.", type: "_nou._tcp.", name: name, port: port)
        service?.delegate = self
        service?.schedule(in: .main, forMode: .common)
        service?.publish()
        print("[NOUPublisher] Publishing _nou._tcp as '\(name)' on port \(port)...")
    }

    func stop() {
        service?.stop()
        service = nil
        print("[NOUPublisher] Stopped advertising")
    }

    // MARK: - NetServiceDelegate

    func netServiceDidPublish(_ sender: NetService) {
        print("[NOUPublisher] Advertising _nou._tcp on port \(port) as '\(sender.name)'")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        print("[NOUPublisher] Failed to publish: \(errorDict)")
    }
}
