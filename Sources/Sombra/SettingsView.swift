import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings = SombraSettings.shared
    @ObservedObject var models = ModelManager.shared
    let onReloadModel: () -> Void

    @State private var newPrompt = ""
    @State private var selectedAppId = ""
    @State private var newAppPrompt = ""

    var body: some View {
        TabView {
            modelTab.tabItem { Label("Modelo", systemImage: "cpu") }
            appearanceTab.tabItem { Label("Aparência", systemImage: "paintpalette") }
            writingTab.tabItem { Label("Escrita", systemImage: "text.cursor") }
            appsTab.tabItem { Label("Apps", systemImage: "app.badge") }
        }
        .frame(width: 500, height: 470)
        .padding()
        .onAppear { models.refreshInstalled() }
    }

    private var activePath: String { ModelLocator.find() ?? "" }

    // MARK: - Modelo

    private var modelTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Modelo ativo")
                    .font(.headline)
                Text((activePath as NSString).lastPathComponent.isEmpty
                     ? "Nenhum (usando heurístico)"
                     : (activePath as NSString).lastPathComponent)
                    .font(.callout).foregroundStyle(.secondary)

                Divider()
                Text("Disponíveis").font(.subheadline).bold()

                if let base = ModelManager.bundledBase,
                   FileManager.default.fileExists(atPath: base.path) {
                    modelRow(url: base, deletable: false, label: "Base (incluído no app)")
                }
                ForEach(models.installed, id: \.path) { url in
                    modelRow(url: url, deletable: true, label: nil)
                }

                HStack {
                    Button("Importar .gguf…") { importModel() }
                    Spacer()
                    Button("Abrir pasta de modelos") { NSWorkspace.shared.open(ModelManager.modelsDir) }
                }
                .padding(.top, 2)

                Divider()
                Text("Baixar modelo").font(.subheadline).bold()
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
                Button("Usar") { settings.modelPath = url.path; onReloadModel() }
            }
            if deletable {
                Button {
                    if url.path == activePath { settings.modelPath = "" }
                    models.remove(url)
                    onReloadModel()
                } label: { Image(systemName: "trash") }
                    .help("Apagar este modelo")
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
                    Label("Instalado", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                } else if isDownloading {
                    ProgressView(value: models.progress).frame(width: 100)
                    Button("Cancelar") { models.cancelDownload() }
                } else {
                    Button("Baixar") { models.download(m) }
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

    // MARK: - Aparência

    private var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sugestão").font(.headline)

            Stepper(value: $settings.suggestionWords, in: 1...10) {
                Text("Palavras por sugestão: \(settings.suggestionWords)")
            }
            Text("Quantas palavras o modelo prevê e mostra de cada vez. Menos = mais rápido.")
                .font(.caption).foregroundStyle(.secondary)

            Toggle("Remover ponto final das sugestões", isOn: $settings.removeTrailingPeriod)

            ColorPicker("Cor da sugestão", selection: Binding(
                get: { settings.ghostColor },
                set: { settings.ghostColor = $0 }
            ))
            VStack(alignment: .leading) {
                Text("Opacidade: \(Int(settings.ghostA * 100))%")
                Slider(value: $settings.ghostA, in: 0.2...1.0)
            }

            Divider()
            Text("Ícone na barra de menu").font(.headline)
            HStack(spacing: 6) {
                ForEach(SombraSettings.menuIconChoices, id: \.self) { emoji in
                    Button(emoji) { settings.menuIcon = emoji }
                        .font(.title2)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(settings.menuIcon == emoji ? Color.accentColor.opacity(0.25) : Color.clear))
                        .buttonStyle(.plain)
                }
            }
            Spacer()
        }
    }

    // MARK: - Escrita

    private var writingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Refinar a escrita").font(.headline)
                Text("Adicione instruções curtas (estilo, idioma…). Elas viram o "
                     + "contexto enviado ao modelo. Sem nada = continuação pura.")
                    .font(.caption).foregroundStyle(.secondary)

                // Campo para digitar e adicionar um prompt.
                HStack {
                    TextField("ex.: Escreva em Português do Brasil.", text: $newPrompt,
                              onCommit: addPrompt)
                        .textFieldStyle(.roundedBorder)
                    Button("Adicionar", action: addPrompt)
                        .disabled(newPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // Prompts já adicionados.
                if settings.customPrompts.isEmpty {
                    Text("Nenhum prompt adicionado.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompts ativos").font(.caption).foregroundStyle(.secondary)
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
                Text("Sugestões prontas").font(.caption).foregroundStyle(.secondary)
                FlowChips(items: SombraSettings.presetPrompts.filter {
                    !settings.customPrompts.contains($0)
                }) { preset in
                    settings.customPrompts.append(preset)
                }
            }
        }
    }

    private func addPrompt() {
        let t = newPrompt.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !settings.customPrompts.contains(t) else { newPrompt = ""; return }
        settings.customPrompts.append(t)
        newPrompt = ""
    }

    // MARK: - Apps (bloqueio + prompts por app)

    private var appsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Bloquear apps").font(.headline)
                Text("Nesses apps a Sombra não lê o texto nem sugere. Recomendado "
                     + "para gerenciadores de senhas e apps sensíveis.")
                    .font(.caption).foregroundStyle(.secondary)

                if settings.blockedApps.isEmpty {
                    Text("Nenhum app bloqueado.").font(.caption).foregroundStyle(.secondary)
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
                Button("Bloquear um app…") {
                    if let a = pickApp() {
                        settings.appNames[a.id] = a.name
                        if !settings.blockedApps.contains(a.id) { settings.blockedApps.append(a.id) }
                    }
                }

                Divider()

                Text("Prompts por app").font(.headline)
                Text("Instruções extras para apps específicos (email, navegador, "
                     + "mensagens…). Somam-se aos prompts gerais.")
                    .font(.caption).foregroundStyle(.secondary)

                let ids = settings.appPrompts.keys.sorted {
                    (settings.appNames[$0] ?? $0).localizedCaseInsensitiveCompare(settings.appNames[$1] ?? $1) == .orderedAscending
                }
                if ids.isEmpty {
                    Text("Nenhum app configurado.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("App:", selection: $selectedAppId) {
                        ForEach(ids, id: \.self) { Text(settings.appNames[$0] ?? $0).tag($0) }
                    }
                    appPromptEditor
                }
                Button("Adicionar app…") {
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
                TextField("ex.: Tom informal e curto.", text: $newAppPrompt, onCommit: addAppPrompt)
                    .textFieldStyle(.roundedBorder)
                Button("Adicionar", action: addAppPrompt)
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
            Button("Remover este app dos prompts") {
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
