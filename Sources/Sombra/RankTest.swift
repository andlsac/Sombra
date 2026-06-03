import Foundation

/// Valida o pipeline "dicionário + ranqueio do modelo" por linha de comando.
///   Sombra --rank "Hoje eu vou para a casa da m"
/// Extrai a palavra parcial ("m"), pega os candidatos do DICIONÁRIO (letras
/// certas), e os reordena pelo MODELO no contexto. Mostra a ordem do dicionário
/// (frequência) vs a ordem do modelo (contexto) + latência.
/// Env: SOMBRA_MODEL, SOMBRA_LANG (pt/en/de, padrão pt), SOMBRA_CONTEXT.
enum RankTest {
    static func run(arguments: [String]) {
        let text: String
        if let i = arguments.firstIndex(of: "--rank"), i + 1 < arguments.count {
            text = arguments[i + 1]
        } else {
            text = "Hoje eu vou para a casa da m"
        }
        let env = ProcessInfo.processInfo.environment
        let lang = env["SOMBRA_LANG"] ?? "pt"
        let ctx = env["SOMBRA_CONTEXT"] ?? ""

        // Palavra parcial (letras finais) + contexto antes dela.
        let partial = String(text.reversed().prefix { $0.isLetter }.reversed())
        let contextPrefix = String(text.dropLast(partial.count))
        guard !partial.isEmpty else {
            FileHandle.standardError.write(Data("[rank] o texto deve terminar numa palavra parcial.\n".utf8))
            exit(2)
        }
        let candidates = WordDictionary.completions(forPartial: partial, language: lang, limit: 10)
        print("[rank] parcial=\"\(partial)\"  contexto=\"\(contextPrefix)\"  (lang=\(lang))")
        print("[rank] dicionário (frequência): \(candidates)")
        guard !candidates.isEmpty else {
            print("[rank] dicionário vazio p/ esse prefixo (cairia em correção/modelo).")
            exit(0)
        }

        let path: String
        if let m = env["SOMBRA_MODEL"], FileManager.default.fileExists(atPath: m) { path = m }
        else if let p = ModelLocator.find() { path = p }
        else { FileHandle.standardError.write(Data("[rank] modelo não encontrado.\n".utf8)); exit(2) }
        print("[rank] modelo: \((path as NSString).lastPathComponent)")
        guard let predictor = LlamaPredictor(modelPath: path) else {
            FileHandle.standardError.write(Data("[rank] falha ao carregar o modelo.\n".utf8)); exit(3)
        }

        for i in 1...3 {
            let sem = DispatchSemaphore(value: 0)
            var ranked: [String] = []
            let start = Date()
            Task {
                ranked = await predictor.rank(candidates: candidates, contextPrefix: contextPrefix,
                                              promptContext: ctx)
                sem.signal()
            }
            sem.wait()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let best = ranked.first ?? "—"
            let suffix = best.count >= partial.count ? String(best.dropFirst(partial.count)) : best
            print("[rank] #\(i)  \(ms) ms\(i == 1 ? " (warmup)" : "")  modelo: \(ranked)")
            if i == 3 { print("[rank] → melhor: \"\(best)\"  (sombra mostraria: \"\(suffix)\")") }
        }
        fflush(stdout)
        _exit(0)
    }
}
