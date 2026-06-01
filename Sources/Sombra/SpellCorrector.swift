import AppKit
import NaturalLanguage

/// Correção/ completação ortográfica usando o corretor nativo do macOS
/// (NSSpellChecker). Rápido, multilíngue e sem custo do modelo de IA.
/// O idioma é DETECTADO do texto recente (não fixo no idioma do sistema), para
/// que escrever em inglês/alemão complete em inglês/alemão — não em português.
enum SpellCorrector {
    private static let checker: NSSpellChecker = {
        let c = NSSpellChecker.shared
        c.automaticallyIdentifiesLanguages = true
        return c
    }()
    private static let recognizer = NLLanguageRecognizer()
    // Tag de "documento" fixo: faz checkSpelling + guesses/correction compartilharem
    // contexto (os guesses costumam vir vazios sem isso).
    private static let docTag = 1

    /// Detecta o idioma do `text` recente e devolve um código aceito pelo
    /// NSSpellChecker (ex.: "pt_BR", "en", "de"). Texto curto demais ou idioma
    /// indisponível → cai no idioma do sistema (`checker.language()`).
    @MainActor
    static func language(for text: String) -> String {
        let t = String(text.suffix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 4 else { return checker.language() }
        recognizer.reset()
        recognizer.processString(t)
        guard let lang = recognizer.dominantLanguage else { return checker.language() }
        switch lang {
        case .portuguese: return "pt_BR"
        case .english:    return "en"
        case .german:     return "de"
        default:
            let code = lang.rawValue
            return checker.availableLanguages.contains(code) ? code : checker.language()
        }
    }

    /// Melhor correção para `word` no `language` dado, ou nil se correta / sem
    /// sugestão. Só age em palavras com 3+ letras (evita ruído em curtas).
    @MainActor
    static func correction(for word: String, language: String? = nil) -> String? {
        guard word.count >= 3, word.allSatisfy({ $0.isLetter }) else { return nil }
        let lang = language ?? checker.language()
        let range = NSRange(location: 0, length: (word as NSString).length)

        // A palavra original é um erro? (também "ensina" o doc para os guesses).
        let wordFlagged = checker.checkSpelling(of: word, startingAt: 0, language: lang,
                                                wrap: false, inSpellDocumentWithTag: docTag,
                                                wordCount: nil).location != NSNotFound

        // Motor de autocorreção NATIVO (correction(forWordRange:)) — bem melhor que
        // o antigo `guesses`, que costuma vir vazio no macOS moderno. Fallback: o
        // 1º palpite de `guesses` (após o checkSpelling acima, mesmo tag).
        var best = checker.correction(forWordRange: range, in: word, language: lang,
                                      inSpellDocumentWithTag: docTag)
        if best == nil {
            best = checker.guesses(forWordRange: range, in: word, language: lang,
                                   inSpellDocumentWithTag: docTag)?.first
        }
        guard let cand = best, cand.lowercased() != word.lowercased() else { return nil }

        // O candidato PRECISA ser uma palavra correta no idioma — evita "correções"
        // lixo (ex.: "entaum" -> "enatam") e mistura de variantes.
        let candFlagged = checker.checkSpelling(of: cand, startingAt: 0, language: lang,
                                                wrap: false, inSpellDocumentWithTag: docTag,
                                                wordCount: nil).location != NSNotFound
        guard !candFlagged else { return nil }

        if wordFlagged { return cand }              // erro real → corrige
        if fold(cand) == fold(word) { return cand } // só falta de acento (voce→você)
        return nil
    }

    /// Completações de uma palavra COMEÇADA no `language` dado (ex.: "comp" em
    /// inglês -> ["complete", "computer", …]). Lista ordenada do mais provável ao
    /// menos; só inclui palavras que estendem o digitado. O ranqueamento final
    /// (ex.: pelo perfil de escrita) fica a cargo de quem chama.
    @MainActor
    static func completions(forPartialWord word: String, language: String? = nil,
                            limit: Int = 12) -> [String] {
        guard word.count >= 2, word.allSatisfy({ $0.isLetter }) else { return [] }
        let lang = language ?? checker.language()
        let range = NSRange(location: 0, length: (word as NSString).length)
        let comps = checker.completions(forPartialWordRange: range, in: word,
                                        language: lang, inSpellDocumentWithTag: 0) ?? []
        return comps.filter {
            $0.count > word.count && $0.lowercased().hasPrefix(word.lowercased())
        }.prefix(limit).map { $0 }
    }

    /// Normaliza removendo acentos e caixa, para comparar "mesma palavra".
    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                  locale: Locale(identifier: "pt_BR"))
    }
}
