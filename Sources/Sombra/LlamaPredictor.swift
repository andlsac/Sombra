import Foundation
import CLlama
import os

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
    // Janela de contexto: agora vem de SombraSettings.contextChars (prefixo longo =
    // mais coerência, mas mais processamento de prompt na GPU / calor).
    /// Modelo instruct/chat (tem template embutido). Tratado via prefill de chat
    /// para CONTINUAR o texto em vez de "responder" como assistente.
    private let isInstruct: Bool
    /// Contador de geração: cada predict() incrementa; gerações antigas (na fila
    /// ou em curso) abortam ao ver um valor mais novo → mata backlog/calor.
    private let genPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    /// true depois que o pré-aquecimento roda uma inferência de verdade — sinal
    /// REAL de "pronto" (não só "objeto criado"). Lido pelo motor (poll) p/ o status.
    private let readyFlag = OSAllocatedUnfairLock(initialState: false)
    var isReady: Bool { readyFlag.withLock { $0 } }

    /// Falha (retorna nil) se o modelo não puder ser carregado.
    init?(modelPath: String, nCtx: Int32 = 2048) {
        guard FileManager.default.fileExists(atPath: modelPath),
              let c = sombra_load(modelPath, nCtx, -1) else {
            return nil
        }
        self.handle = LlamaHandle(ctx: c)
        self.isInstruct = sombra_has_chat_template(c)
        genPtr.initialize(to: 0)
        NSLog("[Sombra] Modelo carregado: \(modelPath) (instruct=\(self.isInstruct))")

        // Pré-aquece: a 1ª inferência compila os pipelines Metal (~vários seg).
        // Fazemos isso já no carregamento para a 1ª sugestão real ser rápida.
        let ready = readyFlag
        queue.async { [handle] in
            var buf = [CChar](repeating: 0, count: 32)
            _ = sombra_complete(handle.ctx, "Olá, ", &buf, 32, 6, 2, true, nil, 0)
            NSLog("[Sombra] Modelo pré-aquecido.")
            ready.withLock { $0 = true }
        }
    }

    deinit {
        // Espera a fila de inferência terminar (warmup/predição em curso) ANTES
        // de liberar o contexto — senão a troca de modelo causa use-after-free
        // (crash) porque sombra_complete ainda estaria usando o ctx liberado.
        let c = handle.ctx
        queue.sync {}
        sombra_free(c)
        genPtr.deallocate()
    }

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

    func setTemperature(_ temperature: Double) {
        let t = Float(max(0, min(temperature, 1.5)))
        queue.async { [handle] in sombra_set_temp(handle.ctx, t) }
    }

    func predict(prefix: String, promptContext: String, maxWords: Int) async -> String? {
        let words = Int32(min(max(maxWords, 1), 15))
        let maxTokens = words * 6 + 4 // teto de segurança (subpalavras)
        let trimDot = SombraSettings.shared.removeTrailingPeriod
        let isInstruct = self.isInstruct
        // Janela de contexto configurável (quantos chars antes do cursor enviar).
        let maxPrefix = SombraSettings.shared.contextChars
        let ctxLower = promptContext.lowercased()
        // Cauda do texto já digitado (minúscula), para detectar quando o modelo
        // REPETE o que você acabou de escrever (eco do próprio corpo).
        let bodyLower = String(prefix.suffix(maxPrefix)).lowercased()
        // Marca esta geração como a mais recente; gerações anteriores abortam.
        genPtr.pointee &+= 1
        let myGen = genPtr.pointee
        let genPtr = self.genPtr
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            queue.async { [handle] in
                // Já obsoleta (usuário digitou de novo): não gera (evita backlog/calor).
                guard genPtr.pointee == myGen else { cont.resume(returning: nil); return }
                let prompt = Self.buildPrompt(prefix: prefix, context: promptContext,
                                              isInstruct: isInstruct, handle: handle,
                                              maxPrefixChars: maxPrefix)
                let cap = 512
                var buf = [CChar](repeating: 0, count: cap)
                let n = sombra_complete(handle.ctx, prompt, &buf, Int32(cap),
                                        maxTokens, words, true, genPtr, myGen)
                guard n > 0 else { cont.resume(returning: nil); return }
                var s = Self.sanitize(String(cString: buf))
                if trimDot {
                    while let last = s.last, last == "." || last == " " {
                        s.removeLast()
                    }
                }
                // Descarta lixo só-símbolos (ex.: '''/***/---), comum em modelos
                // pequenos. Uma sugestão útil precisa de ao menos uma letra/dígito.
                guard s.contains(where: { $0.isLetter || $0.isNumber }) else {
                    cont.resume(returning: nil); return
                }
                // Anti-eco: descarta quando o modelo "repete" as instruções/contexto
                // OU o próprio texto que você acabou de digitar (eco do corpo).
                let sl = s.lowercased()
                if sl.count >= 6,
                   (!ctxLower.isEmpty && ctxLower.contains(sl)) || bodyLower.contains(sl) {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: s.isEmpty ? nil : s)
            }
        }
    }

    /// Remove markup que modelos pequenos às vezes emitem (tags tipo `<s>`,
    /// `<u>...</u>`, `<bos>`), resgatando o texto útil em volta. Também colapsa
    /// espaços/quebras. Não toca em `<` solto sem fechar tag (ex.: "a < b").
    private static let tagRE = try! NSRegularExpression(pattern: "</?[A-Za-z][A-Za-z0-9]*\\s*/?>")
    // Marcadores de markdown que modelos pequenos emitem em texto comum.
    private static let mdRE = try! NSRegularExpression(pattern: "(\\*\\*|__|\\*|`+|~~)")
    // Marcador de lista/título no INÍCIO (ex.: "- ", "* ", "# ", "> ").
    private static let leadMarkerRE = try! NSRegularExpression(pattern: "^\\s*([-*#>]+\\s+)+")
    private static func sanitize(_ raw: String) -> String {
        // Preserva um espaço INICIAL: ele indica fronteira de palavra (o modelo
        // está começando uma palavra nova). Removê-lo cola as palavras ao aceitar
        // ("supermercado"+"comprar"). Só o espaço final/duplicado é descartado.
        let hadLeadingSpace = raw.first == " "
        var s = raw
        for re in [tagRE, mdRE] {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                            withTemplate: "")
        }
        s = leadMarkerRE.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                                  withTemplate: "")
        s = s.replacingOccurrences(of: "\n", with: " ")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.trimmingCharacters(in: .whitespaces)
        if hadLeadingSpace, !s.isEmpty { s = " " + s }
        return s
    }

    /// Papel INTERNO do modelo (system prompt). Define o que a Sombra é e proíbe
    /// os modos de falha que modelos pequenos cometem (preencher lacunas com
    /// "____", rótulos "A)", repetir o texto ou repetir/responder as instruções).
    /// As instruções do usuário entram DEPOIS, como orientação — nunca como texto
    /// a ecoar. Só se aplica a modelos INSTRUCT (com template de chat).
    private static func systemPrompt(userContext: String) -> String {
        var s = L.t(
            "You are a silent inline autocomplete inside the user's text editor. Continue the text from exactly where it stops, in the SAME language, matching its tone and logic. Output ONLY the raw continuation: never repeat or rephrase the existing text, never restate or answer these instructions, never produce blanks, underscores, placeholders, quotes, lists, labels (like \"A)\") or explanations. A short continuation of a few words is fine.",
            "Você é um autocompletar silencioso dentro do editor de texto do usuário. Continue o texto exatamente de onde ele para, na MESMA língua, mantendo o tom e a lógica. Produza APENAS a continuação crua: nunca repita nem reformule o texto existente, nunca repita ou responda estas instruções, nunca gere lacunas, underscores, placeholders, aspas, listas, rótulos (como \"A)\") ou explicações. Uma continuação curta de poucas palavras já basta.")
        let ctx = userContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ctx.isEmpty {
            s += L.t("\n\nUser preferences (guidance only — never output this): ",
                     "\n\nPreferências do usuário (apenas orientação — nunca escreva isto): ") + ctx
        }
        return s
    }

    /// Monta o prompt de geração.
    /// - Modelo BASE: continuação PURA do texto do usuário. Instruções/contexto
    ///   NÃO entram — modelos base só continuam texto, então instruções viram
    ///   lixo ("____") ou eco. É o que dá a melhor qualidade de autocomplete.
    /// - Modelo INSTRUCT: template de chat — system prompt interno (papel) +
    ///   instruções do usuário no turno `user`, e o texto a continuar como PREFILL
    ///   do assistente, para CONTINUAR (não "responder") e sem vazar a instrução.
    /// Chamado dentro da `queue` (serializado). Estático: só usa estado imutável,
    /// evitando capturar `self` (não-Sendable) na closure da fila.
    private static func buildPrompt(prefix: String, context: String, isInstruct: Bool,
                                    handle: LlamaHandle, maxPrefixChars: Int) -> String {
        let body = prefix.count <= maxPrefixChars ? prefix : String(prefix.suffix(maxPrefixChars))
        // Modelo base: pura continuação (ignora instruções/contexto de propósito).
        // Escape de teste: SOMBRA_PROMPT_MODE=raw força a concatenação antiga.
        if !isInstruct {
            if ProcessInfo.processInfo.environment["SOMBRA_PROMPT_MODE"] == "raw", !context.isEmpty {
                return context + " " + body
            }
            return body
        }

        // Instruct: instrução (papel + preferências) no turno user; texto como
        // prefill do assistente.
        let instruction = systemPrompt(userContext: context)
        var buf = [CChar](repeating: 0, count: 4096)
        let n = sombra_build_chat_prefix(handle.ctx, instruction, &buf, 4096)
        guard n > 0 else { return context.isEmpty ? body : context + " " + body }
        return String(cString: buf) + body
    }
}
