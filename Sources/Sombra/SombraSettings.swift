import SwiftUI
import AppKit

extension Notification.Name {
    static let sombraIconChanged = Notification.Name("sombraIconChanged")
    static let sombraShortcutChanged = Notification.Name("sombraShortcutChanged")
    static let sombraDockChanged = Notification.Name("sombraDockChanged")
    static let sombraReloadModel = Notification.Name("sombraReloadModel")
    static let sombraTemperatureChanged = Notification.Name("sombraTemperatureChanged")
}

/// Preferências persistidas (UserDefaults). Observável pela GUI.
final class SombraSettings: ObservableObject {
    static let shared = SombraSettings()
    private let d = UserDefaults.standard

    // Escrita / prompt — lista de instruções curtas que dão contexto ao modelo.
    // Usado como instrução GLOBAL (fallback) quando o modelo ativo não tem uma própria.
    @Published var customPrompts: [String] { didSet { d.set(customPrompts, forKey: K.prompts) } }

    // Instruções de IA POR MODELO: nome do arquivo .gguf -> instrução. Cada modelo
    // guarda a sua (um modelo base ignora; instruct usa). Fallback: customPrompts.
    @Published var modelInstructions: [String: String] { didSet { d.set(modelInstructions, forKey: K.modelInstr) } }

    // Temperatura de amostragem (0 = greedy/estável … 1.5 = mais criativo). Padrão
    // 0.6 — um pouco de variação melhora a naturalidade em modelos base pequenos.
    @Published var modelTemperature: Double {
        didSet {
            d.set(modelTemperature, forKey: K.temp)
            NotificationCenter.default.post(name: .sombraTemperatureChanged, object: nil)
        }
    }

    // Apps onde a Sombra NÃO deve ler/sugerir (bundle ids). Ex.: senhas.
    @Published var blockedApps: [String] { didSet { d.set(blockedApps, forKey: K.blocked) } }

    // Prompts específicos por app: bundleId -> [instruções].
    @Published var appPrompts: [String: [String]] { didSet { d.set(appPrompts, forKey: K.appPrompts) } }

    // Nomes legíveis dos apps (bundleId -> nome), para exibição na GUI.
    @Published var appNames: [String: String] { didSet { d.set(appNames, forKey: K.appNames) } }

    // Modelo selecionado (caminho absoluto do .gguf)
    @Published var modelPath: String { didSet { d.set(modelPath, forKey: K.modelPath) } }

    // Quantas palavras a sugestão deve mostrar (1...10).
    @Published var suggestionWords: Int { didSet { d.set(suggestionWords, forKey: K.words) } }

    // Remover ponto final das sugestões (muitas vezes inútil).
    @Published var removeTrailingPeriod: Bool { didSet { d.set(removeTrailingPeriod, forKey: K.trimDot) } }

    // Mostrar a sugestão como sombra INLINE (colada no cursor, sem bubble).
    @Published var inlineGhost: Bool { didSet { d.set(inlineGhost, forKey: K.inline) } }

    // Atalho dedicado para aceitar a FRASE INTEIRA (Tab segue palavra-por-palavra).
    // keyCode = -1 → desativado.
    @Published var acceptAllKeyCode: Int {
        didSet { d.set(acceptAllKeyCode, forKey: K.acceptAllKey); NotificationCenter.default.post(name: .sombraShortcutChanged, object: nil) }
    }
    @Published var acceptAllModifiers: Int {
        didSet { d.set(acceptAllModifiers, forKey: K.acceptAllMods); NotificationCenter.default.post(name: .sombraShortcutChanged, object: nil) }
    }
    @Published var acceptAllKeyLabel: String { didSet { d.set(acceptAllKeyLabel, forKey: K.acceptAllLabel) } }

    // Descarregar o modelo da RAM após X minutos ocioso (0 = nunca).
    @Published var unloadIdleMinutes: Int { didSet { d.set(unloadIdleMinutes, forKey: K.unload) } }

    // Atalho para aceitar a sugestão (keycode + modificadores em bitmask 1=⌘ 2=⌥ 4=⌃ 8=⇧).
    @Published var acceptKeyCode: Int {
        didSet { d.set(acceptKeyCode, forKey: K.akKey); NotificationCenter.default.post(name: .sombraShortcutChanged, object: nil) }
    }
    @Published var acceptModifiers: Int {
        didSet { d.set(acceptModifiers, forKey: K.akMods); NotificationCenter.default.post(name: .sombraShortcutChanged, object: nil) }
    }
    @Published var acceptKeyLabel: String { didSet { d.set(acceptKeyLabel, forKey: K.akLabel) } }

    // Personalização: aprender com a escrita do usuário e favorecer seus termos.
    @Published var personalizeEnabled: Bool { didSet { d.set(personalizeEnabled, forKey: K.persOn) } }
    @Published var personalizeStrength: Double { didSet { d.set(personalizeStrength, forKey: K.persStr) } } // 0...1
    @Published var storeAllInputs: Bool { didSet { d.set(storeAllInputs, forKey: K.persAll) } }

    // Já viu a introdução (onboarding)?
    @Published var hasSeenOnboarding: Bool { didSet { d.set(hasSeenOnboarding, forKey: K.onboarded) } }

    // Atualizações: buscar automaticamente (opt-in) e se já perguntamos ao usuário.
    @Published var autoCheckUpdates: Bool { didSet { d.set(autoCheckUpdates, forKey: K.autoUpd) } }
    @Published var hasAskedAutoUpdate: Bool { didSet { d.set(hasAskedAutoUpdate, forKey: K.askedUpd) } }

    // Contexto da tela: classifica o app/página e lê o texto visível (OCR) para
    // dar contexto ao modelo. Opt-in (pede permissão de gravação de tela).
    @Published var useScreenContext: Bool { didSet { d.set(useScreenContext, forKey: K.screenCtx) } }

    // Emoji: sugestão via atalho ":nome" (estilo Slack). Gênero (0 neutro, 1 fem,
    // 2 masc) e tom de pele (0 nenhum … 5 escuro) para emojis de pessoa.
    @Published var emojiSuggestionsEnabled: Bool { didSet { d.set(emojiSuggestionsEnabled, forKey: K.emojiOn) } }
    @Published var emojiGender: Int { didSet { d.set(emojiGender, forKey: K.emojiGender) } }
    @Published var emojiSkinTone: Int { didSet { d.set(emojiSkinTone, forKey: K.emojiSkin) } }

    // Mostrar o app no Dock (padrão: só na barra de menu).
    @Published var showInDock: Bool {
        didSet { d.set(showInDock, forKey: K.dock); NotificationCenter.default.post(name: .sombraDockChanged, object: nil) }
    }

    // Emoji do ícone na barra de menu.
    @Published var menuIcon: String {
        didSet {
            d.set(menuIcon, forKey: K.icon)
            NotificationCenter.default.post(name: .sombraIconChanged, object: nil)
        }
    }

    // Aparência da sombra (cor + opacidade)
    @Published var ghostR: Double { didSet { d.set(ghostR, forKey: K.r) } }
    @Published var ghostG: Double { didSet { d.set(ghostG, forKey: K.g) } }
    @Published var ghostB: Double { didSet { d.set(ghostB, forKey: K.b) } }
    @Published var ghostA: Double { didSet { d.set(ghostA, forKey: K.a) } }

    private enum K {
        static let prompts = "customPrompts", modelPath = "modelPath", modelInstr = "modelInstructions"
        static let temp = "modelTemperature"
        static let words = "suggestionWords", icon = "menuIcon", trimDot = "removeTrailingPeriod"
        static let blocked = "blockedApps", appPrompts = "appPrompts", appNames = "appNames"
        static let persOn = "personalizeEnabled", persStr = "personalizeStrength", persAll = "storeAllInputs"
        static let akKey = "acceptKeyCode", akMods = "acceptModifiers", akLabel = "acceptKeyLabel"
        static let onboarded = "hasSeenOnboarding", dock = "showInDock"
        static let autoUpd = "autoCheckUpdates", askedUpd = "hasAskedAutoUpdate"
        static let screenCtx = "useScreenContext"
        static let emojiOn = "emojiSuggestionsEnabled", emojiGender = "emojiGender", emojiSkin = "emojiSkinTone"
        static let inline = "inlineGhost", unload = "unloadIdleMinutes"
        static let acceptAllKey = "acceptAllKeyCode", acceptAllMods = "acceptAllModifiers", acceptAllLabel = "acceptAllKeyLabel"
        static let r = "ghostR", g = "ghostG", b = "ghostB", a = "ghostA"
    }

    private init() {
        // Vazio por padrão: sem preâmbulo => continuação crua (melhor qualidade).
        customPrompts = d.stringArray(forKey: K.prompts) ?? []
        modelInstructions = (d.dictionary(forKey: K.modelInstr) as? [String: String]) ?? [:]
        modelTemperature = d.object(forKey: K.temp) as? Double ?? 0.6
        blockedApps = d.stringArray(forKey: K.blocked) ?? []
        appPrompts = (d.dictionary(forKey: K.appPrompts) as? [String: [String]]) ?? [:]
        appNames = (d.dictionary(forKey: K.appNames) as? [String: String]) ?? [:]
        modelPath = d.string(forKey: K.modelPath) ?? ""
        let w = d.object(forKey: K.words) as? Int ?? 6   // padrão agressivo: frase mais completa
        suggestionWords = min(max(w, 1), 15)
        menuIcon = d.string(forKey: K.icon) ?? "👻"
        removeTrailingPeriod = d.object(forKey: K.trimDot) as? Bool ?? true
        inlineGhost = d.object(forKey: K.inline) as? Bool ?? false
        unloadIdleMinutes = d.object(forKey: K.unload) as? Int ?? 0
        acceptAllKeyCode = d.object(forKey: K.acceptAllKey) as? Int ?? -1   // -1 = desativado
        acceptAllModifiers = d.object(forKey: K.acceptAllMods) as? Int ?? 0
        acceptAllKeyLabel = d.string(forKey: K.acceptAllLabel) ?? L.t("None", "Nenhum")
        personalizeEnabled = d.object(forKey: K.persOn) as? Bool ?? false
        personalizeStrength = d.object(forKey: K.persStr) as? Double ?? 0.4
        storeAllInputs = d.object(forKey: K.persAll) as? Bool ?? true
        acceptKeyCode = d.object(forKey: K.akKey) as? Int ?? 48 // 48 = Tab
        acceptModifiers = d.object(forKey: K.akMods) as? Int ?? 0
        acceptKeyLabel = d.string(forKey: K.akLabel) ?? "Tab"
        hasSeenOnboarding = d.bool(forKey: K.onboarded)
        showInDock = d.bool(forKey: K.dock)
        autoCheckUpdates = d.bool(forKey: K.autoUpd)        // opt-in: padrão desligado
        hasAskedAutoUpdate = d.bool(forKey: K.askedUpd)
        useScreenContext = d.bool(forKey: K.screenCtx)      // opt-in: padrão desligado
        emojiSuggestionsEnabled = d.object(forKey: K.emojiOn) as? Bool ?? true  // só dispara após ":"
        emojiGender = d.object(forKey: K.emojiGender) as? Int ?? 0   // 0 = neutro
        emojiSkinTone = d.object(forKey: K.emojiSkin) as? Int ?? 0   // 0 = nenhum (amarelo)
        // Padrão: cinza discreto. O usuário pode deixar vivo.
        ghostR = d.object(forKey: K.r) as? Double ?? 0.50
        ghostG = d.object(forKey: K.g) as? Double ?? 0.50
        ghostB = d.object(forKey: K.b) as? Double ?? 0.55
        ghostA = d.object(forKey: K.a) as? Double ?? 0.60
    }

    // Emojis + ícones de imagem ("@black"/"@white", carregados do bundle).
    static let menuIconChoices = ["👻", "✍️", "💬", "⌨️", "✨", "🪄", "📝", "🤖", "@black", "@white"]

    /// Prompts prontos para o usuário adicionar com um clique (localizados).
    static var presetPrompts: [String] {
        L.isPT
        ? ["Escreva em Português do Brasil.",
           "Escreva em Português de Portugal.",
           "Write in English.",
           "Escribe en Español.",
           "Misturo Português e Inglês ao escrever.",
           "Mantenha um tom formal e profissional.",
           "Mantenha um tom casual e amigável.",
           "Seja conciso e direto.",
           "Use linguagem clara e simples."]
        : ["Write in English.",
           "Write in Brazilian Portuguese.",
           "Escribe en Español.",
           "I mix English and Portuguese when writing.",
           "Keep a formal, professional tone.",
           "Keep a casual, friendly tone.",
           "Be concise and direct.",
           "Use clear, simple language."]
    }

    /// Contexto global (para a prévia na GUI).
    var promptContext: String { effectiveContext(forApp: nil) }

    /// Chave de um modelo a partir do caminho (nome do arquivo .gguf).
    static func modelKey(forPath path: String) -> String { (path as NSString).lastPathComponent }

    /// Instrução padrão para "Restaurar padrão" — neutra quanto a idioma (não
    /// trava em português; deixa o autocomplete seguir a língua do texto).
    static let defaultInstruction = L.t("Keep a clear, natural tone.",
                                        "Mantenha um tom claro e natural.")

    /// Instrução de IA do modelo `key` (por-modelo). Vazia = sem instrução (só o
    /// system prompt interno). Sem fallback global — assim "Limpar" realmente
    /// zera para aquele modelo.
    func instruction(forModelKey key: String) -> String {
        (modelInstructions[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Contexto efetivo: instrução do MODELO ativo + prompts do app atual.
    func effectiveContext(forApp bundleId: String?, modelKey: String = "") -> String {
        var parts: [String] = []
        let instr = instruction(forModelKey: modelKey)
        if !instr.isEmpty { parts.append(instr) }
        if let b = bundleId, let extra = appPrompts[b] {
            parts += extra.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return parts.joined(separator: " ")
    }

    /// Se a Sombra deve ficar desativada neste app.
    func isBlocked(_ bundleId: String?) -> Bool {
        guard let b = bundleId else { return false }
        return blockedApps.contains(b)
    }

    /// Cor da sombra como NSColor (lado AppKit / overlay).
    var nsGhostColor: NSColor {
        NSColor(srgbRed: ghostR, green: ghostG, blue: ghostB, alpha: ghostA)
    }

    /// Cor da sombra como SwiftUI Color (lado da GUI; binding do ColorPicker).
    var ghostColor: Color {
        get { Color(.sRGB, red: ghostR, green: ghostG, blue: ghostB, opacity: 1.0) }
        set {
            let ns = NSColor(newValue).usingColorSpace(.sRGB) ?? .gray
            ghostR = Double(ns.redComponent)
            ghostG = Double(ns.greenComponent)
            ghostB = Double(ns.blueComponent)
        }
    }
}
