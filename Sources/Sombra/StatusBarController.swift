import AppKit

/// Ícone na barra de menu com toggle, status e ações por app.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let engine: SuggestionEngine
    private let menu = NSMenu()

    // App em foco no momento de abrir o menu (para o toggle "neste app").
    private var currentAppId: String?
    private var currentAppName: String = ""

    init(engine: SuggestionEngine) {
        self.engine = engine
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.toolTip = L.t("Sombra — local-AI autocomplete", "Sombra — autocomplete com IA local")
        applyMenuIcon()
        applyDockPolicy()
        menu.delegate = self
        item.menu = menu
        NotificationCenter.default.addObserver(
            forName: .sombraIconChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyMenuIcon() }
        }
        NotificationCenter.default.addObserver(
            forName: .sombraDockChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyDockPolicy() }
        }
        SettingsWindowController.shared.onReloadModel = { [weak engine] in engine?.reloadModel() }
        // Mantém o status (luz do modelo) em dia quando o estado muda.
        engine.onModelChanged = { [weak self] in MainActor.assumeIsolated { self?.rebuildMenu() } }
        rebuildMenu()
    }

    /// Ícone da barra de menu: emoji (título) ou imagem ("@black"/"@white").
    private func applyMenuIcon() {
        guard let button = item.button else { return }
        let icon = SombraSettings.shared.menuIcon
        if icon == "@black" || icon == "@white" {
            let name = icon == "@black" ? "menu-black" : "menu-white"
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                img.size = NSSize(width: 18, height: 18)
                img.isTemplate = false // respeita a cor escolhida
                button.image = img
                button.title = ""
                return
            }
        }
        button.image = nil
        button.title = icon
    }

    /// Mostra ou não no Dock, conforme a preferência.
    func applyDockPolicy() {
        NSApp.setActivationPolicy(SombraSettings.shared.showInDock ? .regular : .accessory)
    }

    /// Repopula o menu sempre que ele vai abrir (mantém o app atual em dia).
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let toggle = NSMenuItem(
            title: engine.enabled ? L.t("Pause suggestions", "Pausar sugestões")
                                  : L.t("Resume suggestions", "Retomar sugestões"),
            action: #selector(toggleEnabled), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        // Toggle "neste app" — usa o app em foco (não a Sombra).
        let front = NSWorkspace.shared.frontmostApplication
        let ownId = Bundle.main.bundleIdentifier
        if let bid = front?.bundleIdentifier, bid != ownId {
            currentAppId = bid
            currentAppName = front?.localizedName ?? bid
            let blocked = SombraSettings.shared.blockedApps.contains(bid)
            let appItem = NSMenuItem(
                title: blocked ? L.t("Enable in this app (\(currentAppName))", "Ativar neste app (\(currentAppName))")
                               : L.t("Disable in this app (\(currentAppName))", "Desativar neste app (\(currentAppName))"),
                action: #selector(toggleCurrentApp), keyEquivalent: ""
            )
            appItem.target = self
            menu.addItem(appItem)
        } else {
            currentAppId = nil
        }

        menu.addItem(.separator())

        let ax = Permissions.hasAccessibility
        let axItem = NSMenuItem(
            title: ax ? L.t("✅ Accessibility granted", "✅ Acessibilidade concedida")
                      : L.t("⚠️ Grant Accessibility…", "⚠️ Conceder Acessibilidade…"),
            action: ax ? nil : #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        axItem.target = self
        menu.addItem(axItem)

        // Status REAL do modelo (luz colorida). `.ready` só após o pré-aquecimento.
        let dot: String, statusLabel: String
        switch engine.modelState {
        case .ready:    dot = "🟢"; statusLabel = L.t("Model ready", "Modelo pronto")
        case .loading:  dot = "🟠"; statusLabel = L.t("Loading model…", "Carregando modelo…")
        case .unloaded: dot = "⚪️"; statusLabel = L.t("Unloaded (idle)", "Descarregado (ocioso)")
        case .none:     dot = "🔴"; statusLabel = L.t("No model (heuristic)", "Sem modelo (heurístico)")
        }
        let status = NSMenuItem(title: "\(dot) \(statusLabel)", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let model = NSMenuItem(title: L.t("Model: \(engine.modelDescription)", "Modelo: \(engine.modelDescription)"), action: nil, keyEquivalent: "")
        model.isEnabled = false
        menu.addItem(model)

        // Recarregar o modelo sem precisar fechar/abrir o app (recuperação).
        let reload = NSMenuItem(title: L.t("Reload model", "Recarregar modelo"),
                                action: #selector(reloadModel), keyEquivalent: "r")
        reload.target = self
        reload.isEnabled = (engine.modelState != .loading)
        menu.addItem(reload)

        let prefs = NSMenuItem(title: L.t("Preferences…", "Preferências…"), action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let updates = NSMenuItem(title: L.t("Check for updates…", "Verificar atualizações…"),
                                 action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L.t("Quit", "Sair"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func toggleEnabled() {
        engine.setEnabled(!engine.enabled)
        rebuildMenu()
    }

    @objc private func toggleCurrentApp() {
        guard let bid = currentAppId else { return }
        let s = SombraSettings.shared
        if s.blockedApps.contains(bid) {
            s.blockedApps.removeAll { $0 == bid }
        } else {
            s.appNames[bid] = currentAppName
            s.blockedApps.append(bid)
        }
    }

    @objc private func reloadModel() {
        engine.reloadModel()
        rebuildMenu()
    }

    @objc private func openPreferences() {
        SettingsWindowController.shared.show()
    }

    @objc private func checkForUpdates() {
        UpdateWindowController.shared.checkAndPresent(userInitiated: true)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
