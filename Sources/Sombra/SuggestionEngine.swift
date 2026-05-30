import AppKit
import os

/// Orquestra todo o ciclo:
///   ler texto focado -> (debounce) -> prever -> mostrar sombra -> aceitar no Tab.
@MainActor
final class SuggestionEngine {
    private let overlay = GhostOverlay()
    private let keyTap = KeyTap()

    /// Lido pela thread do tap para decidir (sem hop) se consome o Tab.
    /// Mantido em sincronia com `currentSuffix`.
    private let hasSuggestion = OSAllocatedUnfairLock(initialState: false)
    private var predictor: Predictor
    /// Descrição do preditor ativo (para a barra de menu).
    private(set) var modelDescription: String
    /// Notifica a UI quando o modelo ativo muda (para atualizar o menu).
    var onModelChanged: (() -> Void)?

    init() {
        if let path = ModelLocator.find(), let llama = LlamaPredictor(modelPath: path) {
            predictor = llama
            modelDescription = (path as NSString).lastPathComponent
        } else {
            predictor = HeuristicPredictor()
            modelDescription = L.t("Heuristic (no model)", "Heurístico (sem modelo)")
            NSLog("[Sombra] Modelo .gguf não encontrado — usando preditor heurístico.")
        }
    }

    /// Recarrega o preditor a partir do modelo atualmente selecionado.
    /// O carregamento roda fora da main thread (mmap + Metal podem demorar).
    func reloadModel() {
        let path = ModelLocator.find()
        modelDescription = L.t("Loading…", "Carregando…")
        onModelChanged?()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let newPredictor: Predictor
            let desc: String
            if let p = path, let llama = LlamaPredictor(modelPath: p) {
                newPredictor = llama
                desc = (p as NSString).lastPathComponent
            } else {
                newPredictor = HeuristicPredictor()
                desc = L.t("Heuristic (no model)", "Heurístico (sem modelo)")
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight?.cancel()
                self.predictor = newPredictor
                self.modelDescription = desc
                self.dismissGhost()
                self.lastPrefix = ""
                self.onModelChanged?()
            }
        }
    }

    private var pollTimer: Timer?
    private var pendingEval: DispatchWorkItem?
    private var inFlight: Task<Void, Never>?

    private var lastPrefix: String = ""
    private var currentSuffix: String = "" { // sufixo atualmente mostrado na sombra
        didSet {
            let has = !currentSuffix.isEmpty
            hasSuggestion.withLock { $0 = has }
        }
    }
    private var lastCaretRect: CGRect?
    private var lastElementRect: CGRect?
    private var lastBundleId: String?

    // Tipo da sugestão atual: continuação (autocomplete) ou correção ortográfica.
    private enum Mode { case autocomplete, correction }
    private var mode: Mode = .autocomplete
    private var correction: (wrong: String, right: String)?  // palavra errada -> correta

    private(set) var enabled = true

    // Debounce: só prevê após o usuário pausar brevemente a digitação.
    // Curto porque o KV-cache deixou o reprocessamento barato.
    private var lastKeystroke = Date.distantPast
    private let debounce: TimeInterval = 0.07

    // Janela em que o polling é suspenso enquanto o texto aceito é injetado
    // (evita reagir ao estado transitório do campo).
    private var suppressUntil = Date.distantPast

    // MARK: - Ciclo de vida

    func start() {
        let flag = hasSuggestion
        keyTap.onTab = { [weak self] in
            // Roda na THREAD DO TAP. Decisão de consumir é só a leitura atômica
            // (rápida, sem hop). A inserção em si vai para a main de forma async.
            let consume = flag.withLock { $0 }
            if consume, let self {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { _ = self.acceptIfPossible() }
                }
            }
            return consume
        }
        keyTap.onOtherKey = { [weak self] in
            // Roda na THREAD DO TAP: não pode tocar UI/estado direto. Despacha
            // para a main (a tecla é entregue imediatamente, sem esperar).
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastKeystroke = Date()
                    if !self.currentSuffix.isEmpty { self.dismissGhost() }
                    self.scheduleEvaluate()
                }
            }
        }
        keyTap.start()

        // Timer LENTO só de segurança: pega mudanças sem teclado (cursor movido
        // pelo mouse, troca de campo/app). A avaliação rápida é orientada a evento.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        NSLog("[Sombra] Motor iniciado. Acessibilidade: \(Permissions.hasAccessibility)")
    }

    /// Agenda uma avaliação para `debounce` após a última tecla (coalescida:
    /// só a última realmente executa). Nada de AX enquanto se digita rápido.
    private func scheduleEvaluate() {
        pendingEval?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.tick(forced: true) }
        pendingEval = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        pendingEval?.cancel()
        inFlight?.cancel()
        keyTap.stop()
        overlay.hide()
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        if !on { dismissGhost() }
    }

    // MARK: - Personalização (aprende com a sua escrita)

    private var profilePrefix = ""        // âncora p/ registrar palavras digitadas
    private var lastBiasKey = ""          // evita reconstruir o viés à toa
    private var lastBiasBuild = Date.distantPast

    /// Reconstrói o viés (logit bias) se preferências/perfil mudaram (throttled).
    private func refreshBiasIfNeeded() {
        let s = SombraSettings.shared
        guard s.personalizeEnabled else {
            if !lastBiasKey.isEmpty { predictor.setBias(words: [], strength: 0); lastBiasKey = "" }
            return
        }
        let strength = Float(min(max(s.personalizeStrength, 0), 1)) * 5.0 // 0..5 logits
        let words = WritingProfile.shared.topWords()
        let key = "\(String(format: "%.2f", strength))|\(words.count)"
        if key == lastBiasKey { return }
        if !lastBiasKey.isEmpty && Date().timeIntervalSince(lastBiasBuild) < 4 { return }
        predictor.setBias(words: words, strength: strength)
        lastBiasKey = key
        lastBiasBuild = Date()
    }

    /// Registra palavras digitadas (modo "guardar tudo"), avançando no texto.
    private func recordWritingIfEnabled(_ prefix: String) {
        let s = SombraSettings.shared
        guard s.personalizeEnabled, s.storeAllInputs else { return }
        // Âncora = prefixo sem a palavra parcial final (que ainda está sendo digitada).
        var anchor = prefix
        if prefix.last?.isLetter == true,
           let r = prefix.range(of: "[\\p{L}']+$", options: .regularExpression) {
            anchor = String(prefix[..<r.lowerBound])
        }
        if anchor.hasPrefix(profilePrefix) && anchor.count > profilePrefix.count {
            WritingProfile.shared.record(String(anchor.dropFirst(profilePrefix.count)))
            profilePrefix = anchor
        } else if !prefix.hasPrefix(profilePrefix) {
            profilePrefix = anchor // divergiu (editou / trocou de campo): re-ancora
        }
    }

    // MARK: - Loop principal

    private func tick(forced: Bool = false) {
        guard enabled else { return }
        // Não mexe enquanto injetamos o texto aceito.
        guard Date() >= suppressUntil else { return }
        // O timer de segurança respeita o debounce; a avaliação agendada (forced)
        // já dispara no momento certo após a pausa.
        if !forced {
            guard Date().timeIntervalSince(lastKeystroke) >= debounce else { return }
        }

        guard let focus = AXReader.read() else { dismissGhost(); return }
        lastCaretRect = focus.caretRect
        lastElementRect = focus.elementRect
        lastBundleId = focus.appBundleId

        // App bloqueado pelo usuário (ex.: gerenciador de senhas): não sugere.
        if SombraSettings.shared.isBlocked(focus.appBundleId) { dismissGhost(); return }

        // Personalização (modo "guardar tudo"): aprende com o que você digita.
        recordWritingIfEnabled(focus.prefix)

        // Sugere quando o cursor está numa FRONTEIRA de palavra: fim do texto,
        // ou o caractere seguinte não é letra/dígito (espaço, pontuação, quebra).
        // Assim também funciona ao voltar e editar no meio do texto.
        let atTextEnd = focus.length < 0 || focus.caret >= focus.length
        let boundary: Bool
        if atTextEnd {
            boundary = true
        } else if let nc = focus.nextChar {
            boundary = !(nc.isLetter || nc.isNumber)
        } else {
            boundary = true
        }
        guard boundary else { dismissGhost(); return }

        let prefix = focus.prefix
        guard prefix != lastPrefix else {
            // Mesmo prefixo: só reposiciona a sombra (cursor pode ter movido).
            if !currentSuffix.isEmpty {
                overlay.show(suffix: currentSuffix, caretRect: lastCaretRect,
                             elementRect: lastElementRect, isCorrection: mode == .correction)
            }
            return
        }
        lastPrefix = prefix

        // Não sugerir no meio de uma palavra recém-iniciada muito curta.
        guard prefix.count >= 2 else { dismissGhost(); return }

        requestPrediction(prefix: prefix)
    }

    private func requestPrediction(prefix: String) {
        inFlight?.cancel()
        refreshBiasIfNeeded()
        // Contexto: prompts gerais + prompts específicos do app atual.
        let context = SombraSettings.shared.effectiveContext(forApp: lastBundleId)
        inFlight = Task { [weak self] in
            guard let self else { return }
            let suffix = await self.predictor.predict(prefix: prefix, promptContext: context)
            if Task.isCancelled { return }
            await MainActor.run {
                // Só aplica se o prefixo ainda é o atual.
                guard self.lastPrefix == prefix else { return }
                if let suffix, !suffix.isEmpty {
                    // Autocomplete (continuação).
                    self.mode = .autocomplete
                    self.correction = nil
                    self.currentSuffix = suffix
                    self.overlay.show(suffix: suffix, caretRect: self.lastCaretRect,
                                      elementRect: self.lastElementRect)
                } else if let fix = self.spellCorrectionForLastWord(in: prefix) {
                    // Sem autocomplete: oferece correção da última palavra.
                    self.mode = .correction
                    self.correction = fix
                    self.currentSuffix = fix.right
                    self.overlay.show(suffix: fix.right, caretRect: self.lastCaretRect,
                                      elementRect: self.lastElementRect, isCorrection: true)
                } else {
                    self.dismissGhost()
                }
            }
        }
    }

    // MARK: - Aceitar / descartar

    /// Chamado pelo KeyTap quando o Tab é pressionado.
    /// Aceita APENAS a próxima palavra; o restante da sombra permanece.
    /// Retorna true se havia algo a aceitar (e o Tab deve ser consumido).
    private func acceptIfPossible() -> Bool {
        guard enabled, !currentSuffix.isEmpty else { return false }

        // Modo correção: substitui a palavra errada pela correta.
        if mode == .correction, let fix = correction {
            suppressUntil = Date().addingTimeInterval(0.2)
            overlay.hide()
            TextInjector.deleteBackward(count: fix.wrong.count)
            TextInjector.insert(fix.right)
            lastPrefix = String(lastPrefix.dropLast(fix.wrong.count)) + fix.right
            currentSuffix = ""
            correction = nil
            mode = .autocomplete
            return true
        }

        let (word, rest) = Self.firstWord(currentSuffix)
        guard !word.isEmpty else { return false }

        // Suspende o polling enquanto o texto é injetado e "assenta".
        suppressUntil = Date().addingTimeInterval(0.15)
        overlay.hide()
        TextInjector.insert(word)
        lastPrefix += word
        currentSuffix = rest

        // Personalização: a palavra que você ACEITOU é um sinal forte de preferência.
        if SombraSettings.shared.personalizeEnabled,
           !SombraSettings.shared.isBlocked(lastBundleId) {
            WritingProfile.shared.record(word)
        }

        if rest.isEmpty {
            currentSuffix = ""
        } else {
            // Reposiciona a sombra restante após o cursor já ter avançado.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self, !self.currentSuffix.isEmpty else { return }
                if let f = AXReader.read() {
                    self.lastCaretRect = f.caretRect
                    self.lastElementRect = f.elementRect
                }
                self.overlay.show(suffix: self.currentSuffix, caretRect: self.lastCaretRect,
                                  elementRect: self.lastElementRect)
            }
        }
        return true
    }

    /// Separa a próxima "palavra" (espaços iniciais + palavra + 1 espaço final)
    /// do restante. Ex.: "ado pela atenção" -> ("ado ", "pela atenção").
    private static func firstWord(_ s: String) -> (word: String, rest: String) {
        var i = s.startIndex
        let end = s.endIndex
        // espaços iniciais
        while i < end, s[i] == " " { i = s.index(after: i) }
        // corpo da palavra
        while i < end, s[i] != " " { i = s.index(after: i) }
        // inclui um único espaço final, se houver
        if i < end, s[i] == " " { i = s.index(after: i) }
        return (String(s[s.startIndex..<i]), String(s[i..<end]))
    }

    private func dismissGhost() {
        currentSuffix = ""
        correction = nil
        mode = .autocomplete
        overlay.hide()
    }

    /// Correção da última palavra do prefixo, se o cursor estiver logo após ela
    /// (prefixo termina em letra) e ela estiver errada. nil caso contrário.
    private func spellCorrectionForLastWord(in prefix: String) -> (wrong: String, right: String)? {
        let word = String(prefix.reversed().prefix { $0.isLetter }.reversed())
        guard word.count >= 3 else { return nil }
        guard let fix = SpellCorrector.correction(for: word) else { return nil }
        return (word, fix)
    }
}
