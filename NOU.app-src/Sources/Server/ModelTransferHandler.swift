import Foundation
import Hummingbird
import HTTPTypes
import NIOCore

struct ModelTransferHandler {

    struct ModelFileInfo {
        let name: String
        let path: String
        let size: Int64
        let type: String  // "gguf" or "mlx"
    }

    // MARK: - GET /api/models/available

    static func handleAvailable(_ request: Request, _ context: some RequestContext) async throws -> Response {
        let files = scanLocalModels()
        let result: [[String: Any]] = files.map { f in
            ["name": f.name, "path": f.path, "size": f.size, "type": f.type]
        }
        let out = try JSONSerialization.data(withJSONObject: result)
        return Response(
            status: .ok,
            headers: [.contentType: "application/json"],
            body: .init(byteBuffer: .init(data: out))
        )
    }

    // MARK: - GET /api/models/download/{filename}

    static func handleDownload(_ request: Request, _ context: some RequestContext) async throws -> Response {
        guard let filename = context.parameters.get("filename"), !filename.isEmpty else {
            return Response(status: .badRequest,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"missing filename"}"#)))
        }

        // Security: prevent path traversal
        let clean = (filename as NSString).lastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser
        let filePath = home.appendingPathComponent("models").appendingPathComponent(clean)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return Response(status: .notFound,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"file not found"}"#)))
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: filePath.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0

        let responseBody = ResponseBody { writer in
            let handle = try FileHandle(forReadingFrom: filePath)
            defer { handle.closeFile() }
            let chunkSize = 1024 * 1024  // 1MB chunks
            while true {
                let data = handle.readData(ofLength: chunkSize)
                if data.isEmpty { break }
                try await writer.write(ByteBuffer(data: data))
            }
            try await writer.finish(nil)
        }

        return Response(
            status: .ok,
            headers: [
                .contentType: "application/octet-stream",
                .contentLength: String(fileSize),
                .contentDisposition: "attachment; filename=\"\(clean)\"",
            ],
            body: responseBody
        )
    }

    // MARK: - GET /api/models/download-mlx/{name} — Download MLX model as tar stream

    static func handleDownloadMLX(_ request: Request, _ context: some RequestContext) async throws -> Response {
        guard let modelName = context.parameters.get("name"), !modelName.isEmpty else {
            return Response(status: .badRequest,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"missing model name"}"#)))
        }

        // Find the model directory in HuggingFace cache
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hfCache = home.appendingPathComponent(".cache/huggingface/hub")
        let repoName = "models--" + modelName.replacingOccurrences(of: "/", with: "--")
        let snapshotDir = hfCache.appendingPathComponent(repoName).appendingPathComponent("snapshots")

        guard let snapshots = try? FileManager.default.contentsOfDirectory(atPath: snapshotDir.path),
              let latest = snapshots.sorted().last else {
            return Response(status: .notFound,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"error":"model not found in cache"}"#)))
        }

        let modelDir = snapshotDir.appendingPathComponent(latest)

        // Stream a tar of the model directory
        let responseBody = ResponseBody { writer in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-cf", "-", "-C", modelDir.path, "."]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()

            let readHandle = pipe.fileHandleForReading
            let chunkSize = 1024 * 1024  // 1MB
            while true {
                let data = readHandle.readData(ofLength: chunkSize)
                if data.isEmpty { break }
                try await writer.write(ByteBuffer(data: data))
            }
            process.waitUntilExit()
            try await writer.finish(nil)
        }

        let safeName = modelName.replacingOccurrences(of: "/", with: "_")
        return Response(
            status: .ok,
            headers: [
                .contentType: "application/x-tar",
                .contentDisposition: "attachment; filename=\"\(safeName).tar\"",
            ],
            body: responseBody
        )
    }

    // MARK: - Scan local models

    static func scanLocalModels() -> [ModelFileInfo] {
        var files: [ModelFileInfo] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default

        // Check ~/models/ for GGUF files
        let modelsDir = home.appendingPathComponent("models")
        if let contents = try? fm.contentsOfDirectory(atPath: modelsDir.path) {
            for file in contents where file.hasSuffix(".gguf") {
                let path = modelsDir.appendingPathComponent(file)
                let attrs = try? fm.attributesOfItem(atPath: path.path)
                let size = (attrs?[.size] as? Int64) ?? 0
                files.append(ModelFileInfo(name: file, path: path.path, size: size, type: "gguf"))
            }
        }

        // Check HuggingFace cache for MLX models
        let hfCache = home.appendingPathComponent(".cache/huggingface/hub")
        if let repos = try? fm.contentsOfDirectory(atPath: hfCache.path) {
            for repo in repos where repo.hasPrefix("models--mlx-community") {
                let modelName = repo.replacingOccurrences(of: "models--", with: "")
                    .replacingOccurrences(of: "--", with: "/")
                let snapshotDir = hfCache.appendingPathComponent(repo).appendingPathComponent("snapshots")
                guard let snapshots = try? fm.contentsOfDirectory(atPath: snapshotDir.path),
                      let latest = snapshots.sorted().last else { continue }
                let modelDir = snapshotDir.appendingPathComponent(latest)

                // Calculate total size
                var totalSize: Int64 = 0
                if let modelFiles = try? fm.contentsOfDirectory(atPath: modelDir.path) {
                    for f in modelFiles {
                        let attrs = try? fm.attributesOfItem(atPath: modelDir.appendingPathComponent(f).path)
                        totalSize += (attrs?[.size] as? Int64) ?? 0
                    }
                }
                files.append(ModelFileInfo(name: modelName, path: modelDir.path, size: totalSize, type: "mlx"))
            }
        }

        return files.sorted { $0.name < $1.name }
    }
}

// MARK: - HTTPField.Name extensions for Content-Length / Content-Disposition

extension HTTPField.Name {
    static var contentLength: Self { .init("Content-Length")! }
    static var contentDisposition: Self { .init("Content-Disposition")! }
}
