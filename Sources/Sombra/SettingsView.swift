import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings = SombraSettings.shared
    @ObservedObject var models = ModelManager.shared
    @ObservedObject var updater = Updater.shared
    let onReloadModel: () -> Void

    @State private var newPrompt = ""
    @State private var selectedAppId = ""
    @State private var newAppPrompt = ""
    @State private var recordingTarget: String?  // "word" ou "all"
    @State private var shortcutMonitor: Any?

    var body: some View {
        TabView {
            modelTab.tabItem { Label(L.t("Model", "Modelo"), systemImage: "cpu") }
            appearanceTab.tabItem { Label(L.t("Appearance", "Aparência"), systemImage: "paintpalette") }
            writingTab.tabItem { Label(L.t("Writing", "Escrita"), systemImage: "text.cursor") }
            appsTab.tabItem { Label("Apps", systemImage: "app.badge") }
            updatesTab.tabItem { Label(L.t("Updates", "Atualizações"), systemImage: "arrow.down.circle") }
        }
        .frame(width: 500, height: 470)
        .padding()
        .onAppear { models.refreshInstalled() }
    }

    private var activePath: String { ModelLocator.find() ?? "" }

    // MARK: - Atualizações

    private var updatesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("Updates", "Atualizações")).font(.headline)
                Text(L.t("Current version: \(updater.currentVersion)",
                         "Versão atual: \(updater.currentVersion)"))
                    .font(.callout).foregroundStyle(.secondary)

                Toggle(L.t("Check for updates automatically",
                           "Buscar atualizações automaticamente"),
                       isOn: $settings.autoCheckUpdates)
                    .onChange(of: settings.autoCheckUpdates) {
                        settings.hasAskedAutoUpdate = true
                    }
                Text(L.t("When on, Sombra checks GitHub once at launch. This is the only automatic network connection — off by default.",
                         "Quando ligado, a Sombra consulta o GitHub uma vez ao abrir. É a única conexão de rede automática — desligado por padrão."))
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 10) {
                    Button(L.t("Check now", "Verificar agora")) {
                        UpdateWindowController.shared.checkAndPresent(userInitiated: true)
                    }
                    .disabled(updater.checking || updater.downloading)
                    if updater.checking {
                        ProgressView().controlSize(.small)
                        Text(L.t("Checking…", "Verificando…")).font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let r = updater.available {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                        Text(L.t("Version \(r.version) available", "Versão \(r.version) disponível"))
                            .font(.callout)
                        Button(L.t("View…", "Ver…")) { UpdateWindowController.shared.show() }
                            .buttonStyle(.link)
                    }
                } else if updater.upToDate {
                    Text(L.t("You're on the latest version.", "Você está na versão mais recente."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let err = updater.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Modelo

    private var modelTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L.t("Active model", "Modelo ativo"))
                    .font(.headline)
                Text((activePath as NSString).lastPathComponent.isEmpty
                     ? L.t("None (using heuristic)", "Nenhum (usando heurístico)")
                     : (activePath as NSString).lastPathComponent)
                    .font(.callout).foregroundStyle(.secondary)

                Divider()
                Text(L.t("Available", "Disponíveis")).font(.subheadline).bold()

                if let base = ModelManager.bundledBase,
                   FileManager.default.fileExists(atPath: base.path) {
                    modelRow(url: base, deletable: false, label: L.t("Base (bundled)", "Base (incluído no app)"))
                }
                ForEach(models.installed, id: \.path) { url in
                    modelRow(url: url, deletable: true, label: nil)
                }

                HStack {
                    Button(L.t("Import .gguf…", "Importar .gguf…")) { importModel() }
                    Spacer()
                    Button(L.t("Open models folder", "Abrir pasta de modelos")) { NSWorkspace.shared.open(ModelManager.modelsDir) }
                }
                .padding(.top, 2)

                Divider()
                Text(L.t("Download model", "Baixar modelo")).font(.subheadline).bold()
                ForEach(ModelCatalog.all) { catalogRow($0) }

                if let err = models.lastError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    private func modelRow(url: URL, deletable: Bool, label: String?) -> some View {
        let isActive = url.path == activePath
        return HStack(spacing: 8) {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.callout)
                if let label { Text(label).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if !isActive {
                Button(L.t("Use", "Usar")) { settings.modelPath = url.path; onReloadModel() }
            }
            if deletable {
                Button {
                    if url.path == activePath { settings.modelPath = "" }
                    models.remove(url)
                    onReloadModel()
                } label: { Image(systemName: "trash") }
                    .help(L.t("Delete this model", "Apagar este modelo"))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { settings.modelPath = url.path; onReloadModel() }
    }

    private func catalogRow(_ m: CatalogModel) -> some View {
        let isInstalled = models.installed.contains { $0.lastPathComponent == m.filename }
        let isDownloading = models.downloadingFile == m.filename
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(m.name).font(.callout).fontWeight(.medium)
                Spacer()
                if isInstalled {
                    Label(L.t("Installed", "Instalado"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                } else if isDownloading {
                    ProgressView(value: models.progress).frame(width: 100)
                    Button(L.t("Cancel", "Cancelar")) { models.cancelDownload() }
                } else {
                    Button(L.t("Download", "Baixar")) { models.download(m) }
                        .disabled(models.downloadingFile != nil)
                }
            }
            Text(m.summary).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label(Self.sizeLabel(m.approxMB), systemImage: "internaldrive")
                Label(m.hardware, systemImage: "memorychip")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .overlay(Divider(), alignment: .bottom)
    }

    /// Formata o tamanho do download (ex.: 386 MB, 2.0 GB).
    static func sizeLabel(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024.0) : "\(mb) MB"
    }

    private func importModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let t = UTType(filenameExtension: "gguf") { panel.allowedContentTypes = [t] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        models.importFile(url)
        settings.modelPath = ModelManager.modelsDir.appendingPathComponent(url.lastPathComponent).path
        onReloadModel()
    }

    // MARK: - Gravador de atalho

    private func toggleRecording(_ target: String) {
        if recordingTarget != nil { stopRecording(); if recordingTarget == target { return } }
        recordingTarget = target
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
            captureShortcut(ev)
            return nil // consome o evento (não digita no campo)
        }
    }

    private func captureShortcut(_ ev: NSEvent) {
        var mods = 0
        let f = ev.modifierFlags
        if f.contains(.command) { mods |= 1 }
        if f.contains(.option) { mods |= 2 }
        if f.contains(.control) { mods |= 4 }
        if f.contains(.shift) { mods |= 8 }
        settings.acceptKeyCode = Int(ev.keyCode)
        settings.acceptModifiers = mods
        settings.acceptKeyLabel = Self.shortcutLabel(keyCode: Int(ev.keyCode), modifiers: mods, event: ev)
        stopRecording()
    }

    private func stopRecording() {
        if let m = shortcutMonitor { NSEvent.removeMonitor(m); shortcutMonitor = nil }
        recordingTarget = nil
    }

    private func resetShortcut(_ target: String) {
        settings.acceptKeyCode = 48; settings.acceptModifiers = 0; settings.acceptKeyLabel = "Tab"
    }

    static func shortcutLabel(keyCode: Int, modifiers: Int, event: NSEvent?) -> String {
        var s = ""
        if modifiers & 4 != 0 { s += "⌃" }
        if modifiers & 2 != 0 { s += "⌥" }
        if modifiers & 8 != 0 { s += "⇧" }
        if modifiers & 1 != 0 { s += "⌘" }
        switch keyCode {
        case 48: s += "Tab"
        case 36: s += "Return"
        case 49: s += "Space"
        case 53: s += "Esc"
        case 51: s += "Delete"
        case 123: s += "←"; case 124: s += "→"; case 125: s += "↓"; case 126: s += "↑"
        default:
            if let ch = event?.charactersIgnoringModifiers?.first, ch.isLetter || ch.isNumber {
                s += String(ch).uppercased()
            } else {
                s += "Key \(keyCode)"
            }
        }
        return s
    }

    // MARK: - Aparência

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t("Suggestion", "Sugestão")).font(.headline)

            Stepper(value: $settings.suggestionWords, in: 1...15) {
                Text(L.t("Words per suggestion: \(settings.suggestionWords)",
                         "Palavras por sugestão: \(settings.suggestionWords)"))
            }
            Text(L.t("How many words the model predicts and shows at once. Fewer = faster.",
                     "Quantas palavras o modelo prevê e mostra de cada vez. Menos = mais rápido."))
                .font(.caption).foregroundStyle(.secondary)

            Toggle(L.t("Remove trailing period from suggestions",
                       "Remover ponto final das sugestões"), isOn: $settings.removeTrailingPeriod)

            // Atalho para aceitar.
            HStack {
                Text(L.t("Accept shortcut", "Atalho para aceitar"))
                Spacer()
                Button(recordingTarget == "word" ? L.t("Press keys…", "Aperte as teclas…")
                                                 : settings.acceptKeyLabel) { toggleRecording("word") }
                    .frame(minWidth: 90)
                if settings.acceptKeyCode != 48 || settings.acceptModifiers != 0 {
                    Button(L.t("Reset", "Padrão")) { resetShortcut("word") }
                }
            }
            Text(L.t("Press this to accept a suggestion, word by word (default: Tab).",
                     "Aperte isto para aceitar a sugestão, palavra por palavra (padrão: Tab)."))
                .font(.caption).foregroundStyle(.secondary)

            ColorPicker(L.t("Suggestion color", "Cor da sugestão"), selection: Binding(
                get: { settings.ghostColor },
                set: { settings.ghostColor = $0 }
            ))
            VStack(alignment: .leading) {
                Text(L.t("Opacity: \(Int(settings.ghostA * 100))%",
                         "Opacidade: \(Int(settings.ghostA * 100))%"))
                Slider(value: $settings.ghostA, in: 0.2...1.0)
            }

            Divider()
            Text(L.t("Menu bar icon", "Ícone na barra de menu")).font(.headline)
            HStack(spacing: 6) {
                ForEach(SombraSettings.menuIconChoices, id: \.self) { iconButton($0) }
            }

            Toggle(L.t("Show in Dock", "Mostrar no Dock"), isOn: $settings.showInDock)
            Text(L.t("By default Sombra lives only in the menu bar.",
                     "Por padrão a Sombra fica só na barra de menu."))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func iconButton(_ choice: String) -> some View {
        let selected = settings.menuIcon == choice
        let isImage = choice.hasPrefix("@")
        Button { settings.menuIcon = choice } label: {
            Group {
                if isImage, let img = Self.menuIconImage(choice) {
                    Image(nsImage: img).resizable().frame(width: 20, height: 20)
                } else {
                    Text(choice).font(.title2)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.3)
                               : (isImage ? Color(white: 0.5).opacity(0.4) : Color.clear)))
        }
        .buttonStyle(.plain)
    }

    static func menuIconImage(_ choice: String) -> NSImage? {
        let name = choice == "@black" ? "menu-black" : "menu-white"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Escrita

    private var writingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("Refine writing", "Refinar a escrita")).font(.headline)
                Text(L.t("Add short instructions (style, language…). They become the context sent to the model. Empty = raw continuation.",
                         "Adicione instruções curtas (estilo, idioma…). Elas viram o contexto enviado ao modelo. Sem nada = continuação pura."))
                    .font(.caption).foregroundStyle(.secondary)

                // Campo para digitar e adicionar um prompt.
                HStack {
                    TextField(L.t("e.g.: Write in English.", "ex.: Escreva em Português do Brasil."),
                              text: $newPrompt, onCommit: addPrompt)
                        .textFieldStyle(.roundedBorder)
                    Button(L.t("Add", "Adicionar"), action: addPrompt)
                        .disabled(newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // Prompts já adicionados.
                if settings.customPrompts.isEmpty {
                    Text(L.t("No prompts added.", "Nenhum prompt adicionado.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("Active prompts", "Prompts ativos")).font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(settings.customPrompts.enumerated()), id: \.offset) { idx, p in
                            HStack {
                                Image(systemName: "text.quote").foregroundStyle(.secondary)
                                Text(p).font(.callout)
                                Spacer()
                                Button { settings.customPrompts.remove(at: idx) }
                                    label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.textBackgroundColor)))
                        }
                    }
                }

                Divider()

                // Presets prontos para adicionar com um clique.
                Text(L.t("Ready-made suggestions", "Sugestões prontas")).font(.caption).foregroundStyle(.secondary)
                FlowChips(items: SombraSettings.presetPrompts.filter {
                    !settings.customPrompts.contains($0)
                }) { preset in
                    settings.customPrompts.append(preset)
                }

                Divider()
                learningSection
            }
        }
    }

    private func addPrompt() {
        let t = newPrompt.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !settings.customPrompts.contains(t) else { newPrompt = ""; return }
        settings.customPrompts.append(t)
        newPrompt = ""
    }

    // Personalização: aprende com a sua escrita e favorece seus termos.
    private var learningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("Learn from my writing", "Aprender com a minha escrita")).font(.headline)
            Text(L.t("Sombra keeps a local list of the words you use and gently favors them in suggestions. It stays on your Mac.",
                     "A Sombra mantém uma lista local das palavras que você usa e as favorece nas sugestões. Fica só no seu Mac."))
                .font(.caption).foregroundStyle(.secondary)

            Toggle(L.t("Enable personalization", "Ativar personalização"), isOn: $settings.personalizeEnabled)

            if settings.personalizeEnabled {
                VStack(alignment: .leading) {
                    Text(L.t("Favor my words: \(Int(settings.personalizeStrength * 100))%",
                             "Favorecer minhas palavras: \(Int(settings.personalizeStrength * 100))%"))
                    HStack {
                        Text("Off").font(.caption2).foregroundStyle(.secondary)
                        Slider(value: $settings.personalizeStrength, in: 0...1)
                        Text("Max").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(L.t("Subtle at low values; too high may occasionally suggest a less fitting word.",
                         "Sutil em valores baixos; muito alto pode às vezes sugerir uma palavra menos adequada."))
                    .font(.caption).foregroundStyle(.secondary)

                Toggle(L.t("Also learn from everything I type (not only accepted suggestions)",
                           "Aprender também com tudo que eu digito (não só sugestões aceitas)"),
                       isOn: $settings.storeAllInputs)

                HStack {
                    Text(L.t("\(WritingProfile.shared.wordCount) words learned",
                             "\(WritingProfile.shared.wordCount) palavras aprendidas"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L.t("Clear learned data", "Limpar dados aprendidos")) {
                        WritingProfile.shared.clear()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Apps (bloqueio + prompts por app)

    private var appsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("Block apps", "Bloquear apps")).font(.headline)
                Text(L.t("In these apps Sombra won't read text or suggest. Recommended for password managers and sensitive apps.",
                         "Nesses apps a Sombra não lê o texto nem sugere. Recomendado para gerenciadores de senhas e apps sensíveis."))
                    .font(.caption).foregroundStyle(.secondary)

                if settings.blockedApps.isEmpty {
                    Text(L.t("No apps blocked.", "Nenhum app bloqueado.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(settings.blockedApps, id: \.self) { id in
                        HStack {
                            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                            Text(settings.appNames[id] ?? id).font(.callout)
                            Spacer()
                            Button { settings.blockedApps.removeAll { $0 == id } }
                                label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                    }
                }
                Button(L.t("Block an app…", "Bloquear um app…")) {
                    if let a = pickApp() {
                        settings.appNames[a.id] = a.name
                        if !settings.blockedApps.contains(a.id) { settings.blockedApps.append(a.id) }
                    }
                }

                Divider()

                Text(L.t("Per-app prompts", "Prompts por app")).font(.headline)
                Text(L.t("Extra instructions for specific apps (email, browser, messaging…). Added on top of the general prompts.",
                         "Instruções extras para apps específicos (email, navegador, mensagens…). Somam-se aos prompts gerais."))
                    .font(.caption).foregroundStyle(.secondary)

                let ids = settings.appPrompts.keys.sorted {
                    (settings.appNames[$0] ?? $0).localizedCaseInsensitiveCompare(settings.appNames[$1] ?? $1) == .orderedAscending
                }
                if ids.isEmpty {
                    Text(L.t("No apps configured.", "Nenhum app configurado.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("App:", selection: $selectedAppId) {
                        ForEach(ids, id: \.self) { Text(settings.appNames[$0] ?? $0).tag($0) }
                    }
                    appPromptEditor
                }
                Button(L.t("Add app…", "Adicionar app…")) {
                    if let a = pickApp() {
                        settings.appNames[a.id] = a.name
                        if settings.appPrompts[a.id] == nil { settings.appPrompts[a.id] = [] }
                        selectedAppId = a.id
                    }
                }
            }
        }
        .onAppear {
            if selectedAppId.isEmpty { selectedAppId = settings.appPrompts.keys.sorted().first ?? "" }
        }
    }

    @ViewBuilder
    private var appPromptEditor: some View {
        if !selectedAppId.isEmpty, let prompts = settings.appPrompts[selectedAppId] {
            HStack {
                TextField(L.t("e.g.: Casual and short tone.", "ex.: Tom informal e curto."),
                          text: $newAppPrompt, onCommit: addAppPrompt)
                    .textFieldStyle(.roundedBorder)
                Button(L.t("Add", "Adicionar"), action: addAppPrompt)
                    .disabled(newAppPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(Array(prompts.enumerated()), id: \.offset) { idx, p in
                HStack {
                    Image(systemName: "text.quote").foregroundStyle(.secondary)
                    Text(p).font(.callout)
                    Spacer()
                    Button {
                        var arr = settings.appPrompts[selectedAppId] ?? []
                        if idx < arr.count { arr.remove(at: idx); settings.appPrompts[selectedAppId] = arr }
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
            }
            Button(L.t("Remove this app from prompts", "Remover este app dos prompts")) {
                settings.appPrompts[selectedAppId] = nil
                selectedAppId = settings.appPrompts.keys.sorted().first ?? ""
            }
            .foregroundStyle(.red)
        }
    }

    private func addAppPrompt() {
        let t = newAppPrompt.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !selectedAppId.isEmpty else { newAppPrompt = ""; return }
        var arr = settings.appPrompts[selectedAppId] ?? []
        if !arr.contains(t) { arr.append(t); settings.appPrompts[selectedAppId] = arr }
        newAppPrompt = ""
    }

    /// Abre um seletor em /Applications e devolve (bundleId, nome) do app escolhido.
    private func pickApp() -> (id: String, name: String)? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let url = panel.url,
              let b = Bundle(url: url), let id = b.bundleIdentifier else { return nil }
        let name = (b.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return (id, name)
    }
}

/// Lista de "chips" clicáveis que quebram em várias linhas.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text(item).font(.caption)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
