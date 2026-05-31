import AppKit

/// Correção ortográfica da última palavra usando o corretor nativo do macOS
/// (NSSpellChecker). Rápido, multilíngue (usa os idiomas do sistema) e sem
/// custo do modelo de IA.
enum SpellCorrector {
    private static let checker: NSSpellChecker = {
        let c = NSSpellChecker.shared
        c.automaticallyIdentifiesLanguages = true
        return c
    }()

    /// Melhor correção para `word`, ou nil se estiver correta / sem sugestão.
    /// Só age em palavras com 3+ letras (evita ruído em palavras curtas).
    @MainActor
    static func correction(for word: String) -> String? {
        guard word.count >= 3, word.allSatisfy({ $0.isLetter }) else { return nil }

        let full = NSRange(location: 0, length: (word as NSString).length)
        let guesses = checker.guesses(forWordRange: full, in: word,
                                      language: checker.language(),
                                      inSpellDocumentWithTag: 0)
        guard let best = guesses?.first,
              best.lowercased() != word.lowercased() else { return nil }

        // Sinalizada como erro pelo corretor → aceita a melhor sugestão.
        let flagged = checker.checkSpelling(of: word, startingAt: 0).location != NSNotFound
        if flagged { return best }

        // Não sinalizada, mas pode ser só FALTA DE ACENTO (ex.: "voce" → "você",
        // "entao" → "então"). Nesse caso o macOS não marca como erro. Só corrige
        // se a diferença for apenas de acento/caixa (mesmas letras "sem acento"),
        // para nunca trocar uma palavra correta por outra (ex.: "então"→"estão").
        if fold(best) == fold(word) { return best }
        return nil
    }

    /// true se a palavra é sinalizada como ERRADA pelo corretor. Usado para
    /// descartar completações no meio da palavra que formam não-palavras
    /// (ex.: "canc" + "lar" = "canclar").
    @MainActor
    static func isMisspelled(_ word: String) -> Bool {
        guard word.count >= 3, word.allSatisfy({ $0.isLetter }) else { return false }
        return checker.checkSpelling(of: word, startingAt: 0).location != NSNotFound
    }

    /// Normaliza removendo acentos e caixa, para comparar "mesma palavra".
    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                  locale: Locale(identifier: "pt_BR"))
    }
}
