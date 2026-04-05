import Foundation

/// NOU独自リレーへの逆方向WebSocket接続クライアント。
/// リレーサーバー (nou-relay.fly.dev) にダイアルアウトし、
/// 転送されてきたHTTPリクエストをlocalhost:4001で処理して返す。
actor RelayClient {
    static let shared = RelayClient()
    private init() {
        migrateSecretToKeychain()
    }

    // MARK: - State

    private var task: Task<Void, Never>?
    private(set) var isConnected = false
    private(set) var publicURL: String = ""
    private(set) var nodeID: String = ""

    // MARK: - Config keys

    // Always use HTTPS — never fall back to plain HTTP
    private let relayBaseURL = "https://nou-relay.fly.dev"
    private let nodeIDKey    = "nou.relay.nodeID"  // non-sensitive, UserDefaults OK

    // MARK: - Public API

    /// リレーに接続する。すでに接続中なら何もしない。
    func connect() {
        guard task == nil else { return }
        task = Task { await runLoop() }
    }

    /// v2.1→v2.2 移行: UserDefaultsのシークレットをKeychainに移してから削除する。
    private nonisolated func migrateSecretToKeychain() {
        let legacyKey = "nou.relay.secret"
        if let oldSecret = UserDefaults.standard.string(forKey: legacyKey), !oldSecret.isEmpty {
            if KeychainHelper.get(key: "secret") == nil {
                KeychainHelper.set(key: "secret", value: oldSecret)
                print("[Relay] Migrated secret from UserDefaults to Keychain")
            }
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

    /// リレーから切断する。
    func disconnect() {
        task?.cancel()
        task = nil
        isConnected = false
        publicURL = ""
    }

    var snapshot: [String: Any] {
        ["connected": isConnected, "public_url": publicURL, "node_id": nodeID]
    }

    // MARK: - Registration

    private func ensureRegistered() async -> (nodeID: String, secret: String, wsURL: String)? {
        // nodeID is non-sensitive — UserDefaults is fine
        let stored_id  = UserDefaults.standard.string(forKey: nodeIDKey) ?? ""
        // secret is sensitive — Keychain only
        let stored_sec = KeychainHelper.get(key: "secret") ?? ""

        if !stored_id.isEmpty && !stored_sec.isEmpty {
            // Only wss:// — never plain ws://
            let ws = relayBaseURL.replacingOccurrences(of: "https://", with: "wss://") + "/ws"
            return (stored_id, stored_sec, ws)
        }

        // 新規登録 (server always assigns UUID; any body is ignored)
        guard let url = URL(string: relayBaseURL + "/api/register") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nid = json["node_id"] as? String,
              let sec = json["secret"] as? String,
              let ws  = json["ws_url"] as? String else { return nil }

        UserDefaults.standard.set(nid, forKey: nodeIDKey)
        KeychainHelper.set(key: "secret", value: sec)  // Store secret in Keychain, not UserDefaults
        print("[Relay] Registered as node: \(nid)")
        return (nid, sec, ws)
    }

    // MARK: - Connection loop

    private func runLoop() async {
        while !Task.isCancelled {
            guard let creds = await ensureRegistered() else {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                continue
            }

            print("[Relay] Connecting to \(creds.wsURL)")
            await runSession(creds: creds)

            // 切断後は5秒待ってリトライ
            isConnected = false
            publicURL = ""
            if !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func runSession(creds: (nodeID: String, secret: String, wsURL: String)) async {
        guard let url = URL(string: creds.wsURL) else { return }

        let wsTask = URLSession.shared.webSocketTask(with: url)
        wsTask.resume()

        // Hello
        let hello: [String: Any] = [
            "type": "hello",
            "node_id": creds.nodeID,
            "secret": creds.secret,
            "label": Host.current().name ?? creds.nodeID
        ]
        guard let helloData = try? JSONSerialization.data(withJSONObject: hello),
              let helloStr  = String(data: helloData, encoding: .utf8) else { return }
        try? await wsTask.send(.string(helloStr))

        // Welcome
        guard let welcomeMsg = try? await wsTask.receive(),
              case .string(let wStr) = welcomeMsg,
              let wJson = try? JSONSerialization.jsonObject(with: Data(wStr.utf8)) as? [String: Any],
              let pu = wJson["public_url"] as? String else {
            wsTask.cancel(with: .normalClosure, reason: nil)
            return
        }

        nodeID    = creds.nodeID
        publicURL = pu
        isConnected = true
        print("[Relay] Connected. Public URL: \(pu)")

        // Heartbeat
        let pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s
                try? await wsTask.send(.string(#"{"type":"pong"}"#))
            }
        }

        // Message loop
        while !Task.isCancelled {
            guard let msg = try? await wsTask.receive() else { break }
            if case .string(let text) = msg {
                await handleMessage(text, wsTask: wsTask)
            }
        }

        pingTask.cancel()
        wsTask.cancel(with: .normalClosure, reason: nil)
    }

    // MARK: - Request handling

    private func handleMessage(_ text: String, wsTask: URLSessionWebSocketTask) async {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type_ = json["type"] as? String, type_ == "req" else { return }

        let reqID  = json["req_id"]  as? String ?? ""
        let method = json["method"]  as? String ?? "GET"
        let path   = json["path"]    as? String ?? "/"
        let hdrs   = json["headers"] as? [String: String] ?? [:]
        let bodyB64 = json["body_b64"] as? String ?? ""
        let bodyData = Data(base64Encoded: bodyB64) ?? Data()

        // Forward to local proxy
        guard let localURL = URL(string: "http://127.0.0.1:4001\(path)") else {
            await sendError(reqID: reqID, message: "bad path", wsTask: wsTask)
            return
        }

        var req = URLRequest(url: localURL, timeoutInterval: 120)
        req.httpMethod = method
        req.httpBody   = bodyData
        for (k, v) in hdrs {
            req.setValue(v, forHTTPHeaderField: k)
        }
        // Mark as relay/external request for billing
        req.setValue("relay", forHTTPHeaderField: "X-NOU-Source")

        let isStream = hdrs["accept"]?.contains("text/event-stream") ?? false
            || (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any])?["stream"] as? Bool == true

        if isStream {
            await handleStreamRequest(reqID: reqID, urlReq: req, wsTask: wsTask)
        } else {
            await handleSimpleRequest(reqID: reqID, urlReq: req, wsTask: wsTask)
        }
    }

    private func handleSimpleRequest(reqID: String, urlReq: URLRequest, wsTask: URLSessionWebSocketTask) async {
        do {
            let (data, response) = try await URLSession.shared.data(for: urlReq)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 200
            let ct = http?.value(forHTTPHeaderField: "Content-Type") ?? "application/json"

            let header: [String: Any] = [
                "type": "res_header", "req_id": reqID,
                "status": status, "headers": ["content-type": ct]
            ]
            if let s = jsonString(header) { try? await wsTask.send(.string(s)) }

            let chunk: [String: Any] = [
                "type": "res_chunk", "req_id": reqID,
                "data_b64": data.base64EncodedString()
            ]
            if let s = jsonString(chunk) { try? await wsTask.send(.string(s)) }

            let done: [String: Any] = ["type": "res_done", "req_id": reqID]
            if let s = jsonString(done) { try? await wsTask.send(.string(s)) }

        } catch {
            await sendError(reqID: reqID, message: error.localizedDescription, wsTask: wsTask)
        }
    }

    private func handleStreamRequest(reqID: String, urlReq: URLRequest, wsTask: URLSessionWebSocketTask) async {
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: urlReq)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 200

            let header: [String: Any] = [
                "type": "res_header", "req_id": reqID,
                "status": status,
                "headers": ["content-type": "text/event-stream", "cache-control": "no-cache"]
            ]
            if let s = jsonString(header) { try? await wsTask.send(.string(s)) }

            for try await line in bytes.lines {
                if Task.isCancelled { break }
                let lineData = (line + "\n").data(using: .utf8) ?? Data()
                let chunk: [String: Any] = [
                    "type": "res_chunk", "req_id": reqID,
                    "data_b64": lineData.base64EncodedString()
                ]
                if let s = jsonString(chunk) { try? await wsTask.send(.string(s)) }
            }

            let done: [String: Any] = ["type": "res_done", "req_id": reqID]
            if let s = jsonString(done) { try? await wsTask.send(.string(s)) }

        } catch {
            await sendError(reqID: reqID, message: error.localizedDescription, wsTask: wsTask)
        }
    }

    private func sendError(reqID: String, message: String, wsTask: URLSessionWebSocketTask) async {
        let msg: [String: Any] = ["type": "res_err", "req_id": reqID, "message": message]
        if let s = jsonString(msg) { try? await wsTask.send(.string(s)) }
    }

    private func jsonString(_ obj: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}
