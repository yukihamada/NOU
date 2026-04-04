import Foundation

enum CodeExecutionPlugin {
    static func execute(_ args: [String: Any]) async -> String {
        guard let language = args["language"] as? String,
              let code = args["code"] as? String else {
            return "Error: missing 'language' or 'code' parameter"
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        switch language {
        case "python":
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", code]
        case "shell":
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", code]
        default:
            return "Error: unsupported language '\(language)'. Use 'python' or 'shell'."
        }

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

        // Environment: strip sensitive vars, keep PATH
        var env = ProcessInfo.processInfo.environment
        for key in ["ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "RESEND_API_KEY", "STRIPE_SECRET_KEY"] {
            env.removeValue(forKey: key)
        }
        process.environment = env

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 30_000_000_000)
            if process.isRunning { process.terminate() }
        }

        do {
            try process.run()
            process.waitUntilExit()
            timeoutTask.cancel()

            let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            let exitCode = process.terminationStatus
            var result = ""
            if !stdout.isEmpty { result += stdout }
            if !stderr.isEmpty { result += (result.isEmpty ? "" : "\n") + "STDERR: " + stderr }
            if exitCode != 0 { result += "\nExit code: \(exitCode)" }

            // Truncate large output
            if result.count > 4000 {
                result = String(result.prefix(4000)) + "\n... (output truncated at 4000 chars)"
            }

            return result.isEmpty ? "(no output)" : result
        } catch {
            timeoutTask.cancel()
            return "Error: \(error.localizedDescription)"
        }
    }
}
