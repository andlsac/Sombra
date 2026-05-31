import SwiftUI
import AppKit

/// Introdução rápida mostrada na primeira abertura (avança página a página).
struct OnboardingView: View {
    let onDone: () -> Void
    @ObservedObject private var settings = SombraSettings.shared
    @ObservedObject private var models = ModelManager.shared
    @State private var page = 0
    @State private var selectedModel: CatalogModel?
    private let lastPage = 5

    /// Cor candy por página (multi-candy ao longo do onboarding).
    private var pageTint: Color {
        switch page {
        case 0: return Candy.bondi
        case 1: return Candy.blueberry
        case 2: return Candy.grape
        case 3: return Candy.lime
        case 4: return Candy.tangerine
        default: return Candy.strawberry
        }
    }

    var body: some View {
        ZStack {
            AeroBackground(tint: pageTint)
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(28)

                Divider().opacity(0.4)
                HStack {
                    if page > 0 {
                        Button(L.t("Back", "Voltar")) { page -= 1 }.buttonStyle(.borderless)
                    } else {
                        Button(L.t("Skip", "Pular")) { onDone() }.buttonStyle(.borderless)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(0...lastPage, id: \.self) { i in
                            Circle()
                                .fill(i == page ? pageTint : Color.secondary.opacity(0.3))
                                .frame(width: 7, height: 7)
                        }
                    }
                    Spacer()
                    Button(page == lastPage ? L.t("Get started", "Começar") : L.t("Next", "Avançar")) {
                        if page == lastPage { onDone() } else { page += 1 }
                    }
                    .buttonStyle(GlossyButtonStyle(tint: pageTint))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(16)
            }
        }
        .frame(width: 470, height: 470)
        .tint(pageTint)
        .toggleStyle(GlossyToggleStyle())
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    private var key: String { SombraSettings.shared.acceptKeyLabel }

    @ViewBuilder private var content: some View {
        switch page {
        case 0:
            VStack(spacing: 14) {
                if let app = NSApp.applicationIconImage {
                    Image(nsImage: app).resizable().frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                } else {
                    Text("👻").font(.system(size: 52))
                }
                Text(L.t("Welcome to Sombra", "Bem-vindo à Sombra")).font(.title2).bold()
                Text(L.t("Local-AI autocomplete for macOS. It suggests how to continue what you type, right next to the cursor. Everything runs on your Mac.",
                         "Autocomplete com IA local no macOS. Ela sugere como continuar o que você digita, ali ao lado do cursor. Tudo roda no seu Mac."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            modelStep
        case 3:
            step(icon: "⌨️",
                 title: L.t("How to use", "Como usar"),
                 text: L.t("Type normally. A faint suggestion appears by the cursor — press \(key) to accept it, word by word. If the last word is misspelled, a correction shows in orange and \(key) replaces it.",
                           "Digite normalmente. Uma sugestão clara aparece ao lado do cursor — aperte \(key) para aceitar, palavra por palavra. Se a última palavra estiver errada, a correção aparece em laranja e o \(key) substitui."))
        case 4:
            VStack(spacing: 14) {
                Text("🔄").font(.system(size: 52))
                Text(L.t("Stay up to date", "Manter atualizada")).font(.title2).bold()
                Text(L.t("Sombra can check GitHub for new versions and install them for you. This is the only automatic network connection — your choice, and you can change it anytime in Preferences.",
                         "A Sombra pode verificar novas versões no GitHub e instalá-las pra você. É a única conexão de rede automática — você decide, e pode mudar quando quiser nas Preferências."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(L.t("Check for updates automatically",
                           "Buscar atualizações automaticamente"),
                       isOn: $settings.autoCheckUpdates)
                    .toggleStyle(.switch)
                    .fixedSize()
            }
            .onAppear { settings.hasAskedAutoUpdate = true }
        default:
            step(icon: "⚙️",
                 title: L.t("You're all set", "Tudo pronto"),
                 text: L.t("Sombra lives in the menu bar (👻). There you can pick a model, change the shortcut, set your writing style, block apps, and more.",
                           "A Sombra fica na barra de menu (👻). Lá você escolhe o modelo, troca o atalho, define seu estilo de escrita, bloqueia apps e mais."))
        }
    }

    // Passo: escolher e baixar o modelo (o app vem sem modelo embutido).
    private var modelStep: some View {
        VStack(spacing: 10) {
            Text("🧠").font(.system(size: 40))
            Text(L.t("Choose a model", "Escolha um modelo")).font(.title2).bold()
            Text(L.t("Sombra runs a local model. Pick one to download — you can change it anytime in Preferences.",
                     "A Sombra usa um modelo local. Escolha um para baixar — dá pra trocar quando quiser nas Preferências."))
                .font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(ModelCatalog.all) { m in
                        modelRow(m)
                    }
                }
            }
            .frame(maxHeight: 190)

            if models.downloadingFile != nil {
                VStack(spacing: 3) {
                    ProgressView(value: models.progress)
                    Text(L.t("Downloading… \(Int(models.progress * 100))%",
                             "Baixando… \(Int(models.progress * 100))%"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else if let m = selectedModel, !isInstalled(m) {
                Button(L.t("Download (\(m.approxMB) MB)", "Baixar (\(m.approxMB) MB)")) {
                    models.download(m)
                }
                .buttonStyle(GlossyButtonStyle(tint: Candy.grape))
            } else if let m = selectedModel, isInstalled(m), !isActive(m) {
                Button(L.t("Activate & use", "Ativar e usar")) { activate(m) }
                    .buttonStyle(GlossyButtonStyle(tint: Candy.lime))
            } else if let m = selectedModel, isActive(m) {
                Label(L.t("In use", "Em uso"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            }
            if let e = models.lastError {
                Text(e).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private func modelRow(_ m: CatalogModel) -> some View {
        let installed = isInstalled(m)
        let selected = selectedModel?.id == m.id
        return Button {
            selectedModel = m   // só seleciona; baixar/ativar são explícitos
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.name).font(.callout).bold()
                    Text("\(m.approxMB) MB · \(m.summary)")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Image(systemName: installed ? "checkmark.circle.fill"
                                  : (selected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(installed ? Color.green : (selected ? Color.accentColor : Color.secondary))
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func isInstalled(_ m: CatalogModel) -> Bool {
        models.installed.contains { $0.lastPathComponent == m.filename }
    }

    private func isActive(_ m: CatalogModel) -> Bool {
        ModelManager.modelsDir.appendingPathComponent(m.filename).path == SombraSettings.shared.modelPath
    }

    /// Ativa o modelo (define o caminho e pede ao engine para recarregar).
    private func activate(_ m: CatalogModel) {
        let path = ModelManager.modelsDir.appendingPathComponent(m.filename).path
        guard FileManager.default.fileExists(atPath: path) else { return }
        if SombraSettings.shared.modelPath != path {
            SombraSettings.shared.modelPath = path
            NotificationCenter.default.post(name: .sombraReloadModel, object: nil)
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
                Button(button.0, action: button.1).buttonStyle(GlossyButtonStyle(tint: pageTint))
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
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.level = .floating
            // Vidro: janela não-opaca + barra de título transparente (vibrancy aparece).
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isOpaque = false
            w.backgroundColor = .clear
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
        // Volta para a política preferida (Dock só se o usuário ativou).
        NSApp.setActivationPolicy(SombraSettings.shared.showInDock ? .regular : .accessory)
    }
}
