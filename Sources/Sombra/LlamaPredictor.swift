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
    // Janela de contexto curta: autocomplete não precisa de muito, e prefixo
    // longo = muito processamento de prompt na GPU (calor) em textos grandes.
    private let maxPrefixChars = 320
    /// Modelo instruct/chat (tem template embutido). Tratado via prefill de chat
    /// para CONTINUAR o texto em vez de "responder" como assistente.
    private let isInstruct: Bool
    /// Contador de geração: cada predict() incrementa; gerações antigas (na fila
    /// ou em curso) abortam ao ver um valor mais novo → mata backlog/calor.
    private let genPtr = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

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
        queue.async { [handle] in
            var buf = [CChar](repeating: 0, count: 32)
            _ = sombra_complete(handle.ctx, "Olá, ", &buf, 32, 6, 2, true, nil, 0)
            NSLog("[Sombra] Modelo pré-aquecido.")
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

    func predict(prefix: String, promptContext: String, maxWords: Int) async -> String? {
        let words = Int32(min(max(maxWords, 1), 15))
        let maxTokens = words * 6 + 4 // teto de segurança (subpalavras)
        let trimDot = SombraSettings.shared.removeTrailingPeriod
        let isInstruct = self.isInstruct
        let maxPrefix = self.maxPrefixChars
        let ctxLower = promptContext.lowercased()
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
                // Anti-eco: às vezes o modelo "repete" as instruções de contexto
                // (ex.: "Aguarde 2 palavras para trocar de idioma"). Descarta se o
                // sufixo for um trecho do contexto.
                if !ctxLower.isEmpty, s.count >= 8, ctxLower.contains(s.lowercased()) {
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

    /// Monta o prompt de geração.
    /// - Modelo base: continuação crua (contexto + texto), na mesma linha.
    /// - Modelo instruct: usa o template de chat com PREFILL — instrução no turno
    ///   `user` e o texto a continuar no turno do assistente, para o modelo
    ///   CONTINUAR a escrita em vez de virar "assistente" (ex.: "A resposta é…").
    /// Chamado dentro da `queue` (serializado). Estático: só usa estado imutável,
    /// evitando capturar `self` (não-Sendable) na closure da fila.
    private static func buildPrompt(prefix: String, context: String, isInstruct: Bool,
                                    handle: LlamaHandle, maxPrefixChars: Int) -> String {
        let body = prefix.count <= maxPrefixChars ? prefix : String(prefix.suffix(maxPrefixChars))
        let rawFallback = context.isEmpty ? body : context + " " + body
        guard isInstruct else { return rawFallback }

        // Modo de prompt: SOMBRA_PROMPT_MODE = raw | prefill | user.
        // Padrão `raw` (continuação crua): nos testes com modelos instruct
        // pequenos (Gemma-1B) foi o mais confiável — sem EOG→vazio em textos
        // curtos e sem chatter de assistente ("ok, let's try again"), que o
        // template de chat (prefill/user) induzia. Modelos BASE usam este caminho
        // nativamente e dão a melhor qualidade de autocomplete.
        let mode = ProcessInfo.processInfo.environment["SOMBRA_PROMPT_MODE"] ?? "raw"
        if mode == "raw" { return rawFallback }

        var instruction = L.t(
            "You are an inline writing autocomplete. Continue the user's text in the same language. Reply with ONLY the natural continuation — no explanations, no quotes, no lists, and do not repeat the text already written.",
            "Você é um autocompletar de escrita embutido. Continue o texto do usuário na mesma língua. Responda APENAS com a continuação natural — sem explicações, sem aspas, sem listas e sem repetir o texto já escrito.")
        if !context.isEmpty { instruction += " " + context }

        if mode == "user" {
            // Texto vai DENTRO do turno do usuário; assistente gera a continuação.
            var buf = [CChar](repeating: 0, count: 8192)
            let full = instruction + "\n\n" + body
            let n = sombra_build_chat_prefix(handle.ctx, full, &buf, 8192)
            return n > 0 ? String(cString: buf) : rawFallback
        }

        // prefill (padrão): instrução no turno user, texto no turno do assistente.
        var buf = [CChar](repeating: 0, count: 4096)
        let n = sombra_build_chat_prefix(handle.ctx, instruction, &buf, 4096)
        guard n > 0 else { return rawFallback }
        return String(cString: buf) + body
    }
}
