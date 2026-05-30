import SwiftUI
import AppKit

/// Introdução rápida mostrada na primeira abertura (avança página a página).
struct OnboardingView: View {
    let onDone: () -> Void
    @State private var page = 0
    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)

            Divider()
            HStack {
                if page > 0 {
                    Button(L.t("Back", "Voltar")) { page -= 1 }
                } else {
                    Button(L.t("Skip", "Pular")) { onDone() }
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0...lastPage, id: \.self) { i in
                        Circle()
                            .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                Button(page == lastPage ? L.t("Get started", "Começar") : L.t("Next", "Avançar")) {
                    if page == lastPage { onDone() } else { page += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 380)
    }

    private var key: String { SombraSettings.shared.acceptKeyLabel }

    @ViewBuilder private var content: some View {
        switch page {
        case 0:
            step(icon: "👻",
                 title: L.t("Welcome to Sombra", "Bem-vindo à Sombra"),
                 text: L.t("Local-AI autocomplete for macOS. It suggests how to continue what you type, right next to the cursor. Everything runs on your Mac.",
                           "Autocomplete com IA local no macOS. Ela sugere como continuar o que você digita, ali ao lado do cursor. Tudo roda no seu Mac."))
        case 1:
            step(icon: "🔑",
                 title: L.t("One permission", "Uma permissão"),
                 text: L.t("Sombra needs Accessibility to read the text field you're typing in. Enable it for Sombra in System Settings.",
                           "A Sombra precisa de Acessibilidade para ler o campo onde você digita. Ative a Sombra nos Ajustes do Sistema."),
                 button: (L.t("Open Accessibility settings", "Abrir Acessibilidade"), {
                     if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                         NSWorkspace.shared.open(url)
                     }
                 }))
        case 2:
            step(icon: "⌨️",
                 title: L.t("How to use", "Como usar"),
                 text: L.t("Type normally. A faint suggestion appears by the cursor — press \(key) to accept it, word by word. If the last word is misspelled, a correction shows in orange and \(key) replaces it.",
                           "Digite normalmente. Uma sugestão clara aparece ao lado do cursor — aperte \(key) para aceitar, palavra por palavra. Se a última palavra estiver errada, a correção aparece em laranja e o \(key) substitui."))
        default:
            step(icon: "⚙️",
                 title: L.t("You're all set", "Tudo pronto"),
                 text: L.t("Sombra lives in the menu bar (👻). There you can pick a model, change the shortcut, set your writing style, block apps, and more.",
                           "A Sombra fica na barra de menu (👻). Lá você escolhe o modelo, troca o atalho, define seu estilo de escrita, bloqueia apps e mais."))
        }
    }

    private func step(icon: String, title: String, text: String,
                      button: (String, () -> Void)? = nil) -> some View {
        VStack(spacing: 14) {
            Text(icon).font(.system(size: 52))
            Text(title).font(.title2).bold()
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button.0, action: button.1).buttonStyle(.borderedProminent)
            }
        }
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        // Marca como visto já ao abrir (mesmo que feche cedo, não reaparece).
        SombraSettings.shared.hasSeenOnboarding = true
        if window == nil {
            let view = OnboardingView(onDone: { [weak self] in self?.window?.close() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Sombra"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.level = .floating
            window = w
        }
        // App de menu bar (.accessory) não traz janela pra frente no launch.
        // Vira regular temporariamente para a janela aparecer e receber foco.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // volta a ser só barra de menu
    }
}
