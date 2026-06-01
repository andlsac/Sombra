import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings = SombraSettings.shared
    @ObservedObject var models = ModelManager.shared
    @ObservedObject var updater = Updater.shared
    let onReloadModel: () -> Void

    @State private var selectedAppId = ""
    @State private var newAppPrompt = ""
    @State private var recordingTarget: String?  // "word" ou "all"
    @State private var shortcutMonitor: Any?
    @State private var tab = 0

    // Abas: (EN, PT, símbolo, cor candy) — multi-candy.
    private var tabs: [(String, String, String, Color)] {
        [("Model", "Modelo", "cpu", Candy.bondi),
         ("Behavior", "Comportamento", "slider.horizontal.3", Candy.strawberry),
         ("Writing", "Escrita", "text.cursor", Candy.lime),
         ("Apps", "Apps", "app.badge", Candy.tangerine),
         ("Appearance", "Aparência", "paintpalette", Candy.grape),
         ("Updates", "Atualizações", "arrow.down.circle", Candy.blueberry),
         ("Support", "Doações", "heart.fill", Candy.strawberry)]
    }
    private var tabTint: Color { tabs[min(tab, tabs.count - 1)].3 }

    var body: some View {
        ZStack {
            AeroBackground(tint: tabTint)
            VStack(spacing: 12) {
                tabBar
                Group {
                    switch tab {
                    case 0: modelTab
                    case 1: behaviorTab
                    case 2: writingTab
                    case 3: appsTab
                    case 4: appearanceTab
                    case 5: updatesTab
                    default: donationsTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard(tint: tabTint, cornerRadius: 18)
            }
            .padding(.top, 40)   // espaço p/ a barra de título transparente + botões
            .padding([.horizontal, .bottom], 16)
        }
        .frame(minWidth: 820, minHeight: 600)
        .tint(tabTint)
        .toggleStyle(GlossyToggleStyle())
        .animation(.easeInOut(duration: 0.2), value: tab)
        .onAppear { models.refreshInstalled() }
    }

    /// Barra de abas glossy no topo (opções sempre em cima).
    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<tabs.count, id: \.self) { i in
                let t = tabs[i]
                Button { tab = i } label: {
                    VStack(spacing: 2) {
                        Image(systemName: t.2).font(.system(size: 13, weight: .semibold))
                        Text(L.t(t.0, t.1)).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(tab == i ? Color.white : Color.primary.opacity(0.75))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(tab == i
                                  ? AnyShapeStyle(LinearGradient(colors: [t.3.opacity(0.85), t.3],
                                                                 startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(Color.white.opacity(0.10)))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(.white.opacity(tab == i ? 0.45 : 0.12), lineWidth: 1))
                    )
                    .shadow(color: tab == i ? t.3.opacity(0.30) : .clear, radius: 4, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
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
        let label = Self.shortcutLabel(keyCode: Int(ev.keyCode), modifiers: mods, event: ev)
        if recordingTarget == "all" {
            settings.acceptAllKeyCode = Int(ev.keyCode)
            settings.acceptAllModifiers = mods
            settings.acceptAllKeyLabel = label
        } else {
            settings.acceptKeyCode = Int(ev.keyCode)
            settings.acceptModifiers = mods
            settings.acceptKeyLabel = label
        }
        stopRecording()
    }

    private func stopRecording() {
        if let m = shortcutMonitor { NSEvent.removeMonitor(m); shortcutMonitor = nil }
        recordingTarget = nil
    }

    private func resetShortcut(_ target: String) {
        if target == "all" {
            settings.acceptAllKeyCode = -1; settings.acceptAllModifiers = 0
            settings.acceptAllKeyLabel = L.t("None", "Nenhum")
        } else {
            settings.acceptKeyCode = 48; settings.acceptModifiers = 0; settings.acceptKeyLabel = "Tab"
        }
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

    // MARK: - Comportamento

    private var behaviorTab: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t("Suggestions", "Sugestões")).font(.headline)

            Stepper(value: $settings.suggestionWords, in: 1...15) {
                Text(L.t("Words per suggestion: \(settings.suggestionWords)",
                         "Palavras por sugestão: \(settings.suggestionWords)"))
            }
            Text(L.t("How many words the model predicts and shows at once. Fewer = faster & cooler.",
                     "Quantas palavras o modelo prevê e mostra de cada vez. Menos = mais rápido e frio."))
                .font(.caption).foregroundStyle(.secondary)

            Toggle(L.t("Remove trailing period from suggestions",
                       "Remover ponto final das sugestões"), isOn: $settings.removeTrailingPeriod)

            VStack(alignment: .leading) {
                Text(L.t("Creativity (temperature): \(String(format: "%.1f", settings.modelTemperature))",
                         "Criatividade (temperatura): \(String(format: "%.1f", settings.modelTemperature))"))
                HStack {
                    Text(L.t("Stable", "Estável")).font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $settings.modelTemperature, in: 0...1.2, step: 0.1)
                    Text(L.t("Creative", "Criativo")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(L.t("0 = always the most likely word (stable, can be generic). Higher = more natural and context-aware, but may wander. 0.6 recommended.",
                     "0 = sempre a palavra mais provável (estável, pode ficar genérico). Maior = mais natural e contextual, mas pode divagar. 0.6 recomendado."))
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Text(L.t("Shortcuts", "Atalhos")).font(.subheadline).bold()

            HStack {
                Text(L.t("Accept (word by word)", "Aceitar (palavra por palavra)"))
                Spacer()
                Button(recordingTarget == "word" ? L.t("Press keys…", "Aperte as teclas…")
                                                 : settings.acceptKeyLabel) { toggleRecording("word") }
                    .frame(minWidth: 90)
                if settings.acceptKeyCode != 48 || settings.acceptModifiers != 0 {
                    Button(L.t("Reset", "Padrão")) { resetShortcut("word") }
                }
            }
            HStack {
                Text(L.t("Accept whole suggestion", "Aceitar a frase inteira"))
                Spacer()
                Button(recordingTarget == "all" ? L.t("Press a key…", "Pressione uma tecla…")
                                                 : settings.acceptAllKeyLabel) { toggleRecording("all") }
                    .frame(minWidth: 90)
                if settings.acceptAllKeyCode >= 0 {
                    Button { resetShortcut("all") } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            Text(L.t("Optional separate shortcut: inserts the entire suggestion at once.",
                     "Atalho separado opcional: insere a sugestão inteira de uma vez."))
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Text(L.t("Performance", "Desempenho")).font(.subheadline).bold()
            Picker(L.t("Unload model when idle", "Descarregar modelo ocioso"),
                   selection: $settings.unloadIdleMinutes) {
                Text(L.t("Never", "Nunca")).tag(0)
                Text(L.t("After 2 min", "Após 2 min")).tag(2)
                Text(L.t("After 5 min", "Após 5 min")).tag(5)
                Text(L.t("After 15 min", "Após 15 min")).tag(15)
                Text(L.t("After 30 min", "Após 30 min")).tag(30)
            }
            .pickerStyle(.menu)
            Text(L.t("Frees RAM after idle. Trade-off: the first suggestion after that is slower (the model reloads).",
                     "Libera RAM após ocioso. Contrapartida: a 1ª sugestão depois fica mais lenta (o modelo recarrega)."))
                .font(.caption).foregroundStyle(.secondary)
        }
        }
    }

    // MARK: - Aparência

    private var appearanceTab: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.t("Shadow", "Sombra")).font(.headline)
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
        }
        }
    }

    // MARK: - Doações

    private var donationsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("Support Sombra", "Apoie a Sombra")).font(.headline)
                Text(L.t("Sombra is free and open source. If it's useful to you, a tip is hugely appreciated — totally optional.",
                         "A Sombra é gratuita e de código aberto. Se for útil pra você, uma ajuda é muito bem-vinda — totalmente opcional."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: URL(string: "https://ko-fi.com/andre38264")!) {
                    Label("Ko-fi", systemImage: "cup.and.saucer.fill")
                }.buttonStyle(GlossyButtonStyle(tint: Candy.tangerine))

                Link(destination: URL(string: "https://www.paypal.com/donate/?business=FF3HTRZWDV8HS&no_recurring=0&item_name=Hey+you+%3AD&currency_code=EUR")!) {
                    Label("PayPal", systemImage: "creditcard.fill")
                }.buttonStyle(GlossyButtonStyle(tint: Candy.blueberry))

                Divider()
                Text(L.t("Pix (Brazil)", "Pix (Brasil)")).font(.subheadline).bold()
                HStack {
                    Text("37adbd1c-6e5e-4d2f-916a-04bc892fe496")
                        .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button(L.t("Copy", "Copiar")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("37adbd1c-6e5e-4d2f-916a-04bc892fe496", forType: .string)
                    }.buttonStyle(GlossyButtonStyle(tint: Candy.lime))
                }

                Divider()
                Link(destination: URL(string: "https://github.com/andlsac/Sombra")!) {
                    Label(L.t("Project on GitHub", "Projeto no GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .padding(.horizontal, 2)
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
                Text(L.t("AI instructions", "Instruções para a IA")).font(.headline)
                Text(L.t("Tell the AI about you and how to write (your languages, tone, role…). These guide an internal instruction — they are never typed out. Leave empty for plain continuation.",
                         "Conte à IA sobre você e como escrever (suas línguas, tom, função…). Elas guiam uma instrução interna — nunca são digitadas no texto. Deixe vazio para continuação simples."))
                    .font(.caption).foregroundStyle(.secondary)

                Divider()
                Toggle(L.t("Use screen context (OCR)", "Usar contexto da tela (OCR)"),
                       isOn: $settings.useScreenContext)
                    .onChange(of: settings.useScreenContext) {
                        if settings.useScreenContext { ScreenContext.requestScreenPermission() }
                    }
                Text(L.t("Detects the app/page (email, browser, notes…) and reads visible text so suggestions fit the context. Asks for Screen Recording; off by default.",
                         "Detecta o app/página (email, navegador, notas…) e lê o texto visível para as sugestões combinarem com o contexto. Pede Gravação de Tela; desligado por padrão."))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()

                // Campo único de instruções (estilo Cotypist "Custom AI Instructions").
                ZStack(alignment: .topLeading) {
                    if aiInstructions.wrappedValue.isEmpty {
                        Text(L.t("e.g.: I write in Brazilian Portuguese, English and German. Keep a clear, professional tone.",
                                 "ex.: Escrevo em português do Brasil, inglês e alemão. Mantenha um tom claro e profissional."))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 8).allowsHitTesting(false)
                    }
                    TextEditor(text: aiInstructions)
                        .font(.callout)
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))

                HStack {
                    Spacer()
                    Button(L.t("Clear", "Limpar")) { aiInstructions.wrappedValue = "" }
                        .disabled(aiInstructions.wrappedValue.isEmpty)
                    Button(L.t("Reset to default", "Restaurar padrão")) {
                        aiInstructions.wrappedValue = SombraSettings.defaultInstruction
                    }
                }
                .controlSize(.small)

                Label(L.t("These instructions are saved per model. Active model: \(activeModelKey.isEmpty ? "—" : activeModelKey).",
                          "Estas instruções são salvas por modelo. Modelo ativo: \(activeModelKey.isEmpty ? "—" : activeModelKey)."),
                      systemImage: "cpu")
                    .font(.caption).foregroundStyle(.secondary)
                Label(L.t("Instructions apply to instruct models (e.g. Gemma 1B, Qwen). The base model (Gemma E2B) does plain continuation and ignores them.",
                          "As instruções valem para modelos instruct (ex.: Gemma 1B, Qwen). O modelo base (Gemma E2B) faz continuação pura e as ignora."),
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)

                // Presets prontos: clicar acrescenta uma linha.
                Text(L.t("Ready-made suggestions", "Sugestões prontas")).font(.caption).foregroundStyle(.secondary)
                FlowChips(items: SombraSettings.presetPrompts.filter {
                    !aiInstructions.wrappedValue.localizedCaseInsensitiveContains($0)
                }) { preset in
                    let cur = aiInstructions.wrappedValue
                    aiInstructions.wrappedValue = cur.isEmpty ? preset : cur + "\n" + preset
                }

                Divider()
                learningSection

                Divider()
                emojiSection
            }
        }
    }

    // Sugestão de emoji por atalho ":nome" (estilo Slack).
    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("Emoji shortcut", "Atalho de emoji")).font(.headline)
            Text(L.t("Type \":\" followed by a standard name (e.g. :tada, :fire, :rocket, :thumbsup) and Sombra suggests an emoji. Names are in English (GitHub/Slack style). Accept with the same key as text.",
                     "Digite \":\" seguido de um nome padrão (ex.: :tada, :fire, :rocket, :thumbsup) e a Sombra sugere um emoji. Os nomes são em inglês (estilo GitHub/Slack). Aceite com a mesma tecla do texto."))
                .font(.caption).foregroundStyle(.secondary)

            Toggle(L.t("Enable emoji suggestions", "Ativar sugestão de emoji"),
                   isOn: $settings.emojiSuggestionsEnabled)

            if settings.emojiSuggestionsEnabled {
                Picker(L.t("Gender (people)", "Gênero (pessoas)"), selection: $settings.emojiGender) {
                    Text(L.t("Neutral", "Neutro")).tag(0)
                    Text(L.t("Female", "Feminino")).tag(1)
                    Text(L.t("Male", "Masculino")).tag(2)
                }
                .pickerStyle(.segmented)

                Picker(L.t("Skin tone", "Tom de pele"), selection: $settings.emojiSkinTone) {
                    Text(L.t("None", "Nenhum")).tag(0)
                    Text("🏻").tag(1)
                    Text("🏼").tag(2)
                    Text("🏽").tag(3)
                    Text("🏾").tag(4)
                    Text("🏿").tag(5)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Text(L.t("Preview:", "Prévia:")).font(.caption).foregroundStyle(.secondary)
                    Text(["thumbsup", "raising_hand", "technologist", "wave"]
                        .compactMap { EmojiCatalog.emoji(forQuery: $0) }
                        .joined(separator: "  "))
                        .font(.title3)
                }
            }
        }
    }

    /// Nome do arquivo do modelo ATIVO (o mesmo que o motor carrega via ModelLocator).
    private var activeModelKey: String {
        ModelLocator.find().map { ($0 as NSString).lastPathComponent } ?? ""
    }

    /// Instruções de IA do MODELO ATIVO (estilo Cotypist), um texto livre. Cada
    /// modelo guarda a sua; se ainda não tiver, mostra a global (customPrompts)
    /// como ponto de partida e passa a salvar por-modelo ao editar.
    private var aiInstructions: Binding<String> {
        let key = activeModelKey
        return Binding(
            get: { settings.modelInstructions[key] ?? "" },
            set: { txt in settings.modelInstructions[key] = txt }
        )
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
