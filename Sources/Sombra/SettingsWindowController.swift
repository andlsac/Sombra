import AppKit
import SwiftUI

/// Hospeda a SettingsView (SwiftUI) numa janela AppKit.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    /// Disparado quando o usuário troca o modelo na GUI.
    var onReloadModel: (() -> Void)?

    func show() {
        if window == nil {
            let view = SettingsView(onReloadModel: { [weak self] in self?.onReloadModel?() })
            let hosting = NSHostingController(rootView: view)
            let w = NSWindow(contentViewController: hosting)
            w.title = "Sombra — Preferências"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}
