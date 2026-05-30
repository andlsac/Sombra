import Foundation
import CLlama

/// Preditor real: SmolLM2 (GGUF) via llama.cpp com Metal.
/// As chamadas são serializadas (o contexto llama não é thread-safe).
/// Embrulho para passar o ponteiro C através de closures @Sendable.
/// Seguro porque todas as chamadas ao contexto são serializadas na `queue`.
private struct LlamaHandle: @unchecked Sendable {
    let ctx: OpaquePointer
}

final class LlamaPredictor: Predictor {
    private let handle: LlamaHandle           // sombra_ctx*
    private var ctx: OpaquePointer { handle.ctx }
    private let queue = DispatchQueue(label: "com.sombra.llama", qos: .userInitiated)
    private let maxPrefixChars = 800

    /// Falha (retorna nil) se o modelo não puder ser carregado.
    init?(modelPath: String, nCtx: Int32 = 2048) {
        guard FileManager.default.fileExists(atPath: modelPath),
              let c = sombra_load(modelPath, nCtx, -1) else {
            return nil
        }
        self.handle = LlamaHandle(ctx: c)
        NSLog("[Sombra] Modelo carregado: \(modelPath)")

        // Pré-aquece: a 1ª inferência compila os pipelines Metal (~vários seg).
        // Fazemos isso já no carregamento para a 1ª sugestão real ser rápida.
        queue.async { [handle] in
            var buf = [CChar](repeating: 0, count: 32)
            _ = sombra_complete(handle.ctx, "Olá, ", &buf, 32, 6, 2, true)
            NSLog("[Sombra] Modelo pré-aquecido.")
        }
    }

    deinit { sombra_free(ctx) }

    func setBias(words: [String], strength: Float) {
        let joined = words.joined(separator: "\n")
        queue.async { [handle] in
            if joined.isEmpty || strength <= 0 {
                sombra_set_bias(handle.ctx, nil, 0)
            } else {
                sombra_set_bias(handle.ctx, joined, strength)
            }
        }
    }

    func predict(prefix: String, promptContext: String) async -> String? {
        let prompt = buildPrompt(prefix: prefix, context: promptContext)
        let words = Int32(min(max(SombraSettings.shared.suggestionWords, 1), 10))
        let maxTokens = words * 8 + 4 // teto de segurança (subpalavras)
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            queue.async { [handle] in
                let cap = 512
                var buf = [CChar](repeating: 0, count: cap)
                let n = sombra_complete(handle.ctx, prompt, &buf, Int32(cap),
                                        maxTokens, words, true)
                guard n > 0 else { cont.resume(returning: nil); return }
                var s = String(cString: buf)
                if SombraSettings.shared.removeTrailingPeriod {
                    while let last = s.last, last == "." || last == " " {
                        s.removeLast()
                    }
                }
                cont.resume(returning: s.isEmpty ? nil : s)
            }
        }
    }

    /// Continuação direta do texto digitado, com um preâmbulo leve (o contexto
    /// já vem montado pelo engine — geral + do app atual). Vazio = continuação pura.
    private func buildPrompt(prefix: String, context: String) -> String {
        let body = prefix.count <= maxPrefixChars ? prefix : String(prefix.suffix(maxPrefixChars))
        // Mesma linha (sem \n) para não induzir o modelo a quebrar a frase.
        return context.isEmpty ? body : context + " " + body
    }
}
