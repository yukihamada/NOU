import Foundation

enum ImageGenPlugin {
    static func execute(_ args: [String: Any]) async -> String {
        guard let prompt = args["prompt"] as? String else {
            return "Error: missing 'prompt' parameter"
        }
        let style = args["style"] as? String ?? "realistic"

        // Look for stable-diffusion CLI binary
        let candidates = [
            "/opt/homebrew/bin/sd",
            "/usr/local/bin/sd",
            "/opt/homebrew/bin/stable-diffusion",
            "/usr/local/bin/stable-diffusion"
        ]
        let sdPath = candidates.first { FileManager.default.fileExists(atPath: $0) }

        guard let binary = sdPath else {
            return "Image generation not available. Install stable-diffusion.cpp (brew install stable-diffusion) and place a model at ~/models/sd-v1-4.ckpt"
        }

        let modelPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("models/sd-v1-4.ckpt").path
        guard FileManager.default.fileExists(atPath: modelPath) else {
            return "Error: Model not found at \(modelPath). Download a Stable Diffusion model first."
        }

        let outputPath = NSTemporaryDirectory() + "nou_gen_\(UUID().uuidString).png"

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = [
            "-m", modelPath,
            "-p", "\(prompt), \(style) style",
            "-o", outputPath,
            "--steps", "20"
        ]
        process.standardError = errorPipe
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 120_000_000_000)  // 2 min timeout for image gen
            if process.isRunning { process.terminate() }
        }

        do {
            try process.run()
            process.waitUntilExit()
            timeoutTask.cancel()

            if FileManager.default.fileExists(atPath: outputPath) {
                return "Image generated successfully: \(outputPath)"
            } else {
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                return "Error: Image generation failed. \(stderr.prefix(500))"
            }
        } catch {
            timeoutTask.cancel()
            return "Error: \(error.localizedDescription)"
        }
    }
}
