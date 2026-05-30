import SwiftUI
import AppKit

extension Notification.Name {
    static let sombraIconChanged = Notification.Name("sombraIconChanged")
}

/// Preferências persistidas (UserDefaults). Observável pela GUI.
final class SombraSettings: ObservableObject {
    static let shared = SombraSettings()
    private let d = UserDefaults.standard

    // Escrita / prompt — lista de instruções curtas que dão contexto ao modelo.
    @Published var customPrompts: [String] { didSet { d.set(customPrompts, forKey: K.prompts) } }

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
        static let prompts = "customPrompts", modelPath = "modelPath"
        static let words = "suggestionWords", icon = "menuIcon", trimDot = "removeTrailingPeriod"
        static let blocked = "blockedApps", appPrompts = "appPrompts", appNames = "appNames"
        static let r = "ghostR", g = "ghostG", b = "ghostB", a = "ghostA"
    }

    private init() {
        // Vazio por padrão: sem preâmbulo => continuação crua (melhor qualidade).
        customPrompts = d.stringArray(forKey: K.prompts) ?? []
        blockedApps = d.stringArray(forKey: K.blocked) ?? []
        appPrompts = (d.dictionary(forKey: K.appPrompts) as? [String: [String]]) ?? [:]
        appNames = (d.dictionary(forKey: K.appNames) as? [String: String]) ?? [:]
        modelPath = d.string(forKey: K.modelPath) ?? ""
        let w = d.object(forKey: K.words) as? Int ?? 4
        suggestionWords = min(max(w, 1), 10)
        menuIcon = d.string(forKey: K.icon) ?? "👻"
        removeTrailingPeriod = d.object(forKey: K.trimDot) as? Bool ?? true
        // Padrão: cinza discreto. O usuário pode deixar vivo.
        ghostR = d.object(forKey: K.r) as? Double ?? 0.50
        ghostG = d.object(forKey: K.g) as? Double ?? 0.50
        ghostB = d.object(forKey: K.b) as? Double ?? 0.55
        ghostA = d.object(forKey: K.a) as? Double ?? 0.60
    }

    static let menuIconChoices = ["👻", "✍️", "💬", "⌨️", "✨", "🪄", "📝", "🤖"]

    /// Prompts prontos para o usuário adicionar com um clique.
    static let presetPrompts = [
        "Escreva em Português do Brasil.",
        "Escreva em Português de Portugal.",
        "Write in English.",
        "Escribe en Español.",
        "Misturo Português e Inglês ao escrever.",
        "Mantenha um tom formal e profissional.",
        "Mantenha um tom casual e amigável.",
        "Seja conciso e direto.",
        "Use linguagem clara e simples."
    ]

    /// Contexto global (para a prévia na GUI).
    var promptContext: String { effectiveContext(forApp: nil) }

    /// Contexto efetivo: prompts gerais + prompts do app atual.
    func effectiveContext(forApp bundleId: String?) -> String {
        var prompts = customPrompts
        if let b = bundleId, let extra = appPrompts[b] { prompts += extra }
        return prompts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
