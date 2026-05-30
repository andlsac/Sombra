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

        let r = checker.checkSpelling(of: word, startingAt: 0)
        guard r.location != NSNotFound else { return nil } // já está correta

        let full = NSRange(location: 0, length: (word as NSString).length)
        let guesses = checker.guesses(forWordRange: full, in: word,
                                      language: checker.language(),
                                      inSpellDocumentWithTag: 0)
        guard let best = guesses?.first,
              best.lowercased() != word.lowercased() else { return nil }
        return best
    }
}
