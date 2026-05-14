import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAboutWindow() {
        if window == nil {
            let hostingController = NSHostingController(rootView: AboutView())
            let aboutWindow = NSWindow(contentViewController: hostingController)
            aboutWindow.title = "About \(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "webiqu")"
            aboutWindow.styleMask = [.titled, .closable, .miniaturizable]
            aboutWindow.level = .normal
            aboutWindow.isReleasedWhenClosed = false
            window = aboutWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        if let window {
            centerOnActiveScreen(window)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        if let screen = NSApp.keyWindow?.screen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let origin = NSPoint(
                x: visibleFrame.midX - (window.frame.width / 2),
                y: visibleFrame.midY - (window.frame.height / 2)
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }
    }
}