import Foundation

/// Validação da inferência por linha de comando, sem UI.
enum SelfTest {
    static func run(arguments: [String]) {
        let prompt: String
        if let i = arguments.firstIndex(of: "--selftest"), i + 1 < arguments.count {
            prompt = arguments[i + 1]
        } else {
            prompt = "Bom dia, tudo bem? Estou escrevendo para "
        }

        guard let path = ModelLocator.find() else {
            FileHandle.standardError.write(Data("[selftest] Modelo não encontrado. Rode scripts/download_model.sh\n".utf8))
            exit(2)
        }
        print("[selftest] Modelo: \(path)")
        print("[selftest] Prompt: \"\(prompt)\"")

        guard let predictor = LlamaPredictor(modelPath: path) else {
            FileHandle.standardError.write(Data("[selftest] Falha ao carregar o modelo.\n".utf8))
            exit(3)
        }

        // Teste de personalização: SOMBRA_BIAS="palavra1,palavra2" força o viés.
        if let biasEnv = ProcessInfo.processInfo.environment["SOMBRA_BIAS"], !biasEnv.isEmpty {
            let words = biasEnv.split(separator: ",").map { String($0) }
            let strength = Float(ProcessInfo.processInfo.environment["SOMBRA_BIAS_STRENGTH"] ?? "4") ?? 4
            predictor.setBias(words: words, strength: strength)
            print("[selftest] BIAS aplicado: \(words) força=\(strength)")
        }

        // Roda algumas vezes: a 1ª inclui warmup (pipelines Metal); as
        // seguintes refletem a latência "quente" real por tecla.
        var last: String?
        for i in 1...4 {
            let sem = DispatchSemaphore(value: 0)
            var result: String?
            let start = Date()
            let ctx = ProcessInfo.processInfo.environment["SOMBRA_CONTEXT"] ?? ""
            Task {
                result = await predictor.predict(prefix: prompt, promptContext: ctx, maxWords: SombraSettings.shared.suggestionWords)
                sem.signal()
            }
            sem.wait()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            print("[selftest] #\(i)  latência: \(ms) ms  →  \"\(result ?? "<nil>")\"\(i == 1 ? "  (inclui warmup)" : "")")
            last = result
        }
        print("[selftest] Sugestão: \"\(last ?? "<nil>")\"")
        // _exit evita rodar os destrutores estáticos do ggml-metal, que
        // abortam na finalização do processo (irrelevante: já terminamos).
        // Mas _exit não esvazia os buffers do stdio — flush manual antes.
        fflush(stdout)
        _exit(last == nil ? 1 : 0)
    }
}
