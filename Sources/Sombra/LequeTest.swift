import Foundation

/// Validação do "leque" (candidatos de continuação com contexto) por linha de
/// comando, sem UI. Mede QUALIDADE (os candidatos fazem sentido no contexto?) e
/// LATÊNCIA (decisiva para o calor — o leque roda na fronteira de palavra).
///   Sombra --leque "Hoje eu vou para a casa da "
/// Env: SOMBRA_CONTEXT (instrução/contexto), SOMBRA_LEQUE_K (nº candidatos, 6),
///      SOMBRA_LEQUE_W (palavras por candidato, 1), SOMBRA_MODEL.
enum LequeTest {
    static func run(arguments: [String]) {
        let text: String
        if let i = arguments.firstIndex(of: "--leque"), i + 1 < arguments.count {
            text = arguments[i + 1]
        } else {
            text = "Hoje eu vou para a casa da "
        }
        let env = ProcessInfo.processInfo.environment
        let ctx = env["SOMBRA_CONTEXT"] ?? ""
        let k = Int(env["SOMBRA_LEQUE_K"] ?? "6") ?? 6
        let words = Int(env["SOMBRA_LEQUE_W"] ?? "1") ?? 1

        // Override direto por SOMBRA_MODEL (o ModelLocator pega o 1º .gguf
        // alfabético, ignorando o env — aqui no teste queremos escolher o modelo
        // sem mover arquivos de GB).
        let path: String
        if let m = env["SOMBRA_MODEL"], FileManager.default.fileExists(atPath: m) {
            path = m
        } else if let p = ModelLocator.find() {
            path = p
        } else {
            FileHandle.standardError.write(Data("[leque] Modelo não encontrado.\n".utf8))
            exit(2)
        }
        print("[leque] Modelo: \((path as NSString).lastPathComponent)")
        print("[leque] Texto:  \"\(text)\"  (k=\(k), palavras=\(words))")

        guard let predictor = LlamaPredictor(modelPath: path) else {
            FileHandle.standardError.write(Data("[leque] Falha ao carregar o modelo.\n".utf8))
            exit(3)
        }

        // A 1ª rodada inclui warmup (pipelines Metal); as seguintes são a latência
        // "quente" real por fronteira de palavra.
        for i in 1...3 {
            let sem = DispatchSemaphore(value: 0)
            var res: [String] = []
            let start = Date()
            Task {
                res = await predictor.candidates(prefix: text, promptContext: ctx,
                                                 count: k, maxWords: words)
                sem.signal()
            }
            sem.wait()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            print("[leque] #\(i)  \(ms) ms\(i == 1 ? " (inclui warmup)" : "")  → \(res)")
        }
        fflush(stdout)
        _exit(0)
    }
}
