import Foundation

/// Validação do dicionário embutido por linha de comando, SEM UI e SEM modelo.
///   Sombra --worddict                  → bateria de testes (pt/en/de)
///   Sombra --worddict <lang> <prefixo> → consulta única (ex.: en kubern)
/// Lê words.bin via Bundle.main, env SOMBRA_WORDS, ou Resources/ subindo a árvore.
enum WordDictionaryTest {
    static func run(arguments: [String]) {
        print("[worddict] \(WordDictionary.info)")
        guard WordDictionary.isLoaded else {
            FileHandle.standardError.write(Data(
                "[worddict] words.bin não encontrado. Rode scripts/build_words.py ou aponte SOMBRA_WORDS=...\n".utf8))
            exit(2)
        }

        // Consulta única: --worddict <lang> <prefixo>
        if let i = arguments.firstIndex(of: "--worddict"), i + 2 < arguments.count {
            query(language: arguments[i + 1], partial: arguments[i + 2])
            exit(0)
        }

        // Bateria padrão: cobre completação por frequência, termos técnicos,
        // nomes, acentos e cada idioma.
        let battery: [(String, String)] = [
            ("en", "comp"), ("en", "kubern"), ("en", "docker"), ("en", "the"), ("en", "a"),
            ("pt", "program"), ("pt", "obrig"), ("pt", "desenvolv"), ("pt", "voce"),
            ("de", "entschuld"), ("de", "program"),
        ]
        for (lang, partial) in battery { query(language: lang, partial: partial) }
        exit(0)
    }

    private static func query(language: String, partial: String) {
        // Mede a latência "quente" (a 1ª chamada inclui a carga preguiçosa do
        // arquivo). 10k repetições p/ resolução em ns (o V2 é sub-µs).
        let iters = 10_000
        var comps: [String] = []
        _ = WordDictionary.completions(forPartial: partial, language: language, limit: 8) // aquece
        let start = Date()
        for _ in 0..<iters { comps = WordDictionary.completions(forPartial: partial, language: language, limit: 8) }
        let ns = Int(Date().timeIntervalSince(start) / Double(iters) * 1_000_000_000)
        print("[\(language)] \(partial.padding(toLength: 12, withPad: " ", startingAt: 0))"
              + " \(ns) ns/consulta  → \(comps)")
    }
}
