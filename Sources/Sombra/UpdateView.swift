import SwiftUI
import AppKit

/// Janela que mostra a versão nova, as notas do release e permite instalar.
struct UpdateView: View {
    @ObservedObject var updater = Updater.shared
    let onClose: () -> Void

    private var notes: AttributedString {
        let raw = updater.available?.notes ?? ""
        return (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("👻").font(.system(size: 34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Update available", "Atualização disponível"))
                        .font(.title3).bold()
                    if let r = updater.available {
                        Text(L.t("Sombra \(r.version) — you have \(updater.currentVersion)",
                                 "Sombra \(r.version) — você tem \(updater.currentVersion)"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Text(L.t("What's new", "Novidades")).font(.subheadline).bold()
            ScrollView {
                Text(notes)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
            }
            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 240)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if updater.downloading {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: updater.progress)
                    Text(L.t("Downloading… \(Int(updater.progress * 100))%",
                             "Baixando… \(Int(updater.progress * 100))%"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let err = updater.lastError {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            HStack {
                if let r = updater.available {
                    Button(L.t("View on GitHub", "Ver no GitHub")) {
                        NSWorkspace.shared.open(r.pageURL)
                    }
                    .buttonStyle(.link)
                }
                Spacer()
                Button(L.t("Later", "Depois")) { onClose() }
                    .disabled(updater.downloading)
                Button(L.t("Install & restart", "Instalar e reiniciar")) {
                    if let r = updater.available {
                        Task { await updater.downloadAndInstall(r) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(updater.downloading)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Hospeda a janela de atualização e centraliza "verificar e apresentar".
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()
    private var window: NSWindow?

    /// Verifica atualizações e apresenta o resultado:
    /// - versão nova → abre a janela com as notas;
    /// - já atualizado / erro → alerta (apenas quando o usuário pediu).
    func checkAndPresent(userInitiated: Bool) {
        Task {
            await Updater.shared.checkForUpdates(userInitiated: userInitiated)
            if Updater.shared.available != nil {
                show()
            } else if userInitiated {
                presentAlert()
            }
        }
    }

    private func presentAlert() {
        let u = Updater.shared
        let alert = NSAlert()
        if let err = u.lastError {
            alert.alertStyle = .warning
            alert.messageText = L.t("Couldn't check for updates", "Não foi possível verificar atualizações")
            alert.informativeText = err
        } else {
            alert.alertStyle = .informational
            alert.messageText = L.t("You're up to date", "Você está atualizado")
            alert.informativeText = L.t("Sombra \(u.currentVersion) is the latest version.",
                                        "A Sombra \(u.currentVersion) é a versão mais recente.")
        }
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func show() {
        if window == nil {
            let view = UpdateView(onClose: { [weak self] in self?.window?.close() })
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = L.t("Sombra — Update", "Sombra — Atualização")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.level = .floating
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(SombraSettings.shared.showInDock ? .regular : .accessory)
    }
}
