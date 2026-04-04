import AppKit
import SwiftUI

/// Controls the native SwiftUI dashboard popover shown from the menu bar.
@MainActor
final class DashboardPopoverController {
    static let shared = DashboardPopoverController()

    private var popover: NSPopover?
    private var browser: NOUBrowser?

    private init() {}

    func setBrowser(_ browser: NOUBrowser) {
        self.browser = browser
    }

    /// Toggle the dashboard popover relative to the status bar button.
    func toggle(relativeTo button: NSStatusBarButton) {
        if let popover, popover.isShown {
            popover.close()
            self.popover = nil
            return
        }

        let p = NSPopover()
        p.contentSize = NSSize(width: 380, height: 520)
        p.behavior = .transient
        p.animates = true

        let view = NOUDashboardView(browser: browser)
        let hostingController = NSHostingController(rootView: view)
        p.contentViewController = hostingController

        // Use dark appearance
        p.appearance = NSAppearance(named: .darkAqua)

        p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = p
    }

    func close() {
        popover?.close()
        popover = nil
    }
}
