import AppKit
import Foundation

// MARK: - QuickAIPanel

/// A floating panel for quick AI queries via ⌘⇧N.
/// Sends prompts to the local LLM at localhost:4001 and streams responses.
@MainActor
final class QuickAIPanel: NSObject, NSTextFieldDelegate {

    static let shared = QuickAIPanel()

    private var panel: NSPanel!
    private var inputField: NSTextField!
    private var responseTextView: NSTextView!
    private var responseScrollView: NSScrollView!
    private var thinkingLabel: NSTextField!
    private var containerView: NSView!

    private let panelWidth: CGFloat = 600
    private let inputHeight: CGFloat = 36
    private let initialHeight: CGFloat = 80
    private let maxHeight: CGFloat = 500
    private let bgColor = NSColor(red: 13/255, green: 17/255, blue: 23/255, alpha: 0.96)
    private let textColor = NSColor(red: 230/255, green: 237/255, blue: 243/255, alpha: 1)
    private let borderColor = NSColor(red: 48/255, green: 54/255, blue: 61/255, alpha: 1)
    private let accentColor = NSColor(red: 88/255, green: 166/255, blue: 255/255, alpha: 1)

    /// Conversation history (last 5 exchanges kept in memory)
    private struct Exchange {
        let prompt: String
        let response: String
    }
    private var history: [Exchange] = []
    private var currentStreamTask: Task<Void, Never>?
    private var currentResponse = ""

    // MARK: - Setup

    private override init() {
        super.init()
        setupPanel()
    }

    private func setupPanel() {
        // Panel
        let frame = NSRect(x: 0, y: 0, width: panelWidth, height: initialHeight)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Container with rounded corners
        containerView = NSView(frame: frame)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = bgColor.cgColor
        containerView.layer?.cornerRadius = 12
        containerView.layer?.borderColor = borderColor.cgColor
        containerView.layer?.borderWidth = 1
        containerView.autoresizingMask = [.width, .height]
        panel.contentView = containerView

        // Input field
        let inputY = frame.height - inputHeight - 12
        inputField = NSTextField(frame: NSRect(x: 16, y: inputY, width: panelWidth - 32, height: inputHeight))
        inputField.placeholderString = "Ask AI anything... (Enter to send, Esc to close)"
        inputField.isBordered = false
        inputField.drawsBackground = true
        inputField.backgroundColor = NSColor(red: 22/255, green: 27/255, blue: 34/255, alpha: 1)
        inputField.textColor = textColor
        inputField.font = NSFont.systemFont(ofSize: 14)
        inputField.focusRingType = .none
        inputField.wantsLayer = true
        inputField.layer?.cornerRadius = 8
        inputField.cell?.wraps = false
        inputField.cell?.isScrollable = true
        // Inset text
        if let cell = inputField.cell as? NSTextFieldCell {
            cell.allowedInputSourceLocales = [NSAllRomanInputSourcesLocaleIdentifier]
        }
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(inputSubmitted)
        containerView.addSubview(inputField)

        // Thinking indicator
        thinkingLabel = NSTextField(labelWithString: "")
        thinkingLabel.frame = NSRect(x: 16, y: inputY - 24, width: panelWidth - 32, height: 18)
        thinkingLabel.font = NSFont.systemFont(ofSize: 11)
        thinkingLabel.textColor = accentColor
        thinkingLabel.isHidden = true
        containerView.addSubview(thinkingLabel)

        // Response scroll view (hidden initially)
        let scrollY: CGFloat = 12
        let scrollHeight = inputY - 36 - scrollY
        responseScrollView = NSScrollView(frame: NSRect(x: 16, y: scrollY, width: panelWidth - 32, height: max(scrollHeight, 0)))
        responseScrollView.hasVerticalScroller = true
        responseScrollView.hasHorizontalScroller = false
        responseScrollView.autohidesScrollers = true
        responseScrollView.drawsBackground = false
        responseScrollView.borderType = .noBorder
        responseScrollView.isHidden = true

        responseTextView = NSTextView(frame: responseScrollView.bounds)
        responseTextView.isEditable = false
        responseTextView.isSelectable = true
        responseTextView.drawsBackground = false
        responseTextView.textColor = textColor
        responseTextView.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        responseTextView.textContainerInset = NSSize(width: 4, height: 4)
        responseTextView.isVerticallyResizable = true
        responseTextView.isHorizontallyResizable = false
        responseTextView.textContainer?.widthTracksTextView = true
        responseTextView.autoresizingMask = [.width]

        responseScrollView.documentView = responseTextView
        containerView.addSubview(responseScrollView)
    }

    // MARK: - Show / Hide / Toggle

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        // Center on the screen with the current mouse
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.midY + 100  // slightly above center
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        resizePanel(to: initialHeight)
        responseScrollView.isHidden = true
        thinkingLabel.isHidden = true
        inputField.stringValue = ""
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(inputField)
    }

    func hide() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        panel.orderOut(nil)
    }

    // MARK: - NSTextFieldDelegate

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hide()
            return true
        }
        return false
    }

    @objc private func inputSubmitted() {
        let prompt = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        inputField.stringValue = ""
        sendPrompt(prompt)
    }

    // MARK: - AI Interaction

    private func sendPrompt(_ prompt: String) {
        currentStreamTask?.cancel()
        currentResponse = ""
        thinkingLabel.stringValue = "thinking..."
        thinkingLabel.isHidden = false
        responseTextView.string = ""
        responseScrollView.isHidden = false
        resizePanel(to: 180)

        // Build messages array with history for context
        var messages: [[String: String]] = []
        for exchange in history.suffix(5) {
            messages.append(["role": "user", "content": exchange.prompt])
            messages.append(["role": "assistant", "content": exchange.response])
        }
        messages.append(["role": "user", "content": prompt])

        let capturedPrompt = prompt

        currentStreamTask = Task { [weak self] in
            guard let self else { return }
            await self.streamCompletion(messages: messages, prompt: capturedPrompt)
        }
    }

    private func streamCompletion(messages: [[String: String]], prompt: String) async {
        let url = URL(string: "http://localhost:4001/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": "fast",
            "max_tokens": 500,
            "stream": true,
            "messages": messages.map { $0 as [String: Any] }
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            await showError("Failed to encode request")
            return
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                await showError("Server error (\(code)). Is the proxy running on :4001?")
                return
            }

            thinkingLabel.isHidden = true
            var fullResponse = ""

            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard line.hasPrefix("data: ") else { continue }
                let jsonStr = String(line.dropFirst(6))
                if jsonStr == "[DONE]" { break }

                guard let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let content = delta["content"] as? String else { continue }

                fullResponse += content
                self.currentResponse = fullResponse
                self.responseTextView.string = fullResponse
                // Auto-scroll to bottom
                self.responseTextView.scrollToEndOfDocument(nil)
                // Resize panel based on content
                self.adjustHeight()
            }

            // Save to history
            if !fullResponse.isEmpty {
                history.append(Exchange(prompt: prompt, response: fullResponse))
                if history.count > 5 { history.removeFirst() }
            }

        } catch is CancellationError {
            // cancelled, ignore
        } catch {
            await showError("Connection failed: \(error.localizedDescription)")
        }
    }

    private func showError(_ msg: String) async {
        thinkingLabel.stringValue = msg
        thinkingLabel.textColor = NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
        thinkingLabel.isHidden = false
        // Reset color after a moment
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        thinkingLabel.textColor = accentColor
    }

    // MARK: - Layout

    private func adjustHeight() {
        guard let layoutManager = responseTextView.layoutManager,
              let container = responseTextView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        let textHeight = layoutManager.usedRect(for: container).height + 16
        let needed = inputHeight + 12 + 28 + textHeight + 24
        let target = min(max(needed, 180), maxHeight)
        resizePanel(to: target)
    }

    private func resizePanel(to height: CGFloat) {
        var frame = panel.frame
        let delta = height - frame.height
        frame.origin.y -= delta
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)

        // Re-layout subviews
        let inputY = height - inputHeight - 12
        inputField.frame = NSRect(x: 16, y: inputY, width: panelWidth - 32, height: inputHeight)
        thinkingLabel.frame = NSRect(x: 16, y: inputY - 24, width: panelWidth - 32, height: 18)

        let scrollY: CGFloat = 12
        let scrollHeight = inputY - 36 - scrollY
        responseScrollView.frame = NSRect(x: 16, y: scrollY, width: panelWidth - 32, height: max(scrollHeight, 0))
    }
}
