import AppKit
import os

/// Orquestra todo o ciclo:
///   ler texto focado -> (debounce) -> prever -> mostrar sombra -> aceitar no Tab.
@MainActor
final class SuggestionEngine {
    private let overlay = GhostOverlay()
    private let indicator = IndicatorOverlay()
    private let keyTap = KeyTap()

    // "Armar" sugestões: o texto sugerido só aparece DEPOIS da primeira digitação
    // no campo atual. Antes disso, mostramos apenas o ícone indicador (presença).
    // Uma tecla arma; trocar de app ou de campo (salto grande) desarma.
    private var armed = false
    private var lastFieldOrigin: CGPoint?

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
    private var isReloading = false
    private var modelUnloaded = false   // modelo liberado da RAM por ociosidade

    /// Descarrega o modelo da RAM após X min ocioso (libera RAM). Recarrega na
    /// próxima digitação (a 1ª sugestão depois disso é mais lenta).
    private func checkIdleUnload() {
        let mins = SombraSettings.shared.unloadIdleMinutes
        guard mins > 0, !isReloading, !modelUnloaded, predictor is LlamaPredictor else { return }
        guard Date().timeIntervalSince(lastKeystroke) > Double(mins) * 60 else { return }
        inFlight?.cancel()
        dismissGhost()
        predictor = HeuristicPredictor()   // libera o LlamaPredictor (deinit → free)
        modelUnloaded = true
        modelDescription = L.t("Unloaded (idle)", "Descarregado (ocioso)")
        onModelChanged?()
    }

    func reloadModel() {
        // Evita carregar dois modelos ao mesmo tempo (Metal/llama) — causava crash.
        guard !isReloading else { return }
        isReloading = true
        let path = ModelLocator.find()
        modelDescription = L.t("Loading…", "Carregando…")
        onModelChanged?()
        // Cancela e descarta o preditor atual ANTES de carregar o novo, para não
        // manter dois contextos vivos simultaneamente.
        inFlight?.cancel()
        dismissGhost()
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
                self.isReloading = false
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
    private var lastAtEnd = true   // cursor no fim da linha? → sombra à frente vs abaixo

    // Tipo da sugestão atual: continuação, correção ortográfica ou emoji.
    private enum Mode { case autocomplete, correction, emoji }
    private var mode: Mode = .autocomplete
    private var correction: (wrong: String, right: String)?  // palavra errada -> correta
    // Atalho de emoji ativo: o gatilho digitado (ex.: ":fel") a apagar e o emoji.
    private var emojiReplace: (trigger: String, emoji: String)?

    private(set) var enabled = true

    // Debounce: só prevê após o usuário pausar brevemente a digitação.
    // Curto porque o KV-cache deixou o reprocessamento barato.
    private var lastKeystroke = Date.distantPast
    // Curto = responsivo (estilo Cotypist). Seguro agora que gerações obsoletas
    // são abortadas (cancelamento), então não acumula carga/calor.
    private let debounce: TimeInterval = 0.045

    // Janela em que o polling é suspenso enquanto o texto aceito é injetado
    // (evita reagir ao estado transitório do campo).
    private var suppressUntil = Date.distantPast

    // MARK: - Ciclo de vida

    /// Aplica os atalhos configurados ao KeyTap.
    private func updateShortcut() {
        let s = SombraSettings.shared
        keyTap.acceptKeyCode = CGKeyCode(s.acceptKeyCode)
        keyTap.acceptModifiers = s.acceptModifiers
        // Atalho de aceitar-tudo (opcional): keyCode < 0 = desativado.
        keyTap.acceptAllKeyCode = s.acceptAllKeyCode >= 0 ? CGKeyCode(s.acceptAllKeyCode) : 0xFFFF
        keyTap.acceptAllModifiers = s.acceptAllModifiers
    }

    func start() {
        updateShortcut()
        NotificationCenter.default.addObserver(
            forName: .sombraShortcutChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateShortcut() }
        }
        // Recarrega o modelo quando muda (ex.: baixado no onboarding/Preferências).
        NotificationCenter.default.addObserver(
            forName: .sombraReloadModel, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadModel() }
        }

        let flag = hasSuggestion
        keyTap.onTab = { [weak self] in
            // Roda na THREAD DO TAP. Decisão de consumir é só a leitura atômica
            // (rápida, sem hop). A inserção em si vai para a main de forma async.
            let consume = flag.withLock { $0 }
            if consume, let self {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { _ = self.acceptIfPossible(whole: false) }
                }
            }
            return consume
        }
        keyTap.onAcceptAll = { [weak self] in
            let consume = flag.withLock { $0 }
            if consume, let self {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { _ = self.acceptIfPossible(whole: true) }
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
                    // Acorda o modelo se foi descarregado por ociosidade.
                    if self.modelUnloaded { self.modelUnloaded = false; self.reloadModel() }
                    self.armed = true   // o usuário digitou: a partir daqui pode sugerir
                    if !self.currentSuffix.isEmpty { self.dismissGhost() }
                    self.scheduleEvaluate()
                }
            }
        }
        keyTap.start()

        // Timer LENTO só de segurança: pega mudanças sem teclado (cursor movido
        // pelo mouse, troca de campo/app). A avaliação rápida é orientada a evento.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdleUnload(); self?.tick() }
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
        indicator.hide()
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        if !on { dismissGhost(); indicator.hide() }
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
        // Inclui uma assinatura do CONTEÚDO: antes a key era só força+contagem,
        // então trocar palavras (mesma contagem) não recarregava o viés.
        let key = "\(String(format: "%.2f", strength))|\(words.count)|\(words.joined(separator: ",").hashValue)"
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
            WritingProfile.shared.resetSequence()
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

        guard let focus = AXReader.read() else { dismissGhost(); indicator.hide(); return }
        lastCaretRect = focus.caretRect
        lastElementRect = focus.elementRect

        // App bloqueado pelo usuário (ex.: gerenciador de senhas): nem ícone, nem sugestão.
        if SombraSettings.shared.isBlocked(focus.appBundleId) {
            lastBundleId = focus.appBundleId
            dismissGhost(); indicator.hide(); return
        }

        // "Desarma" ao trocar de app, ou de campo na mesma janela (salto grande
        // da origem do campo) — volta a mostrar só o ícone até digitar de novo.
        let originNow = focus.elementRect?.origin
        if focus.appBundleId != lastBundleId {
            armed = false
        } else if let o = originNow, let p = lastFieldOrigin,
                  abs(o.x - p.x) > 60 || abs(o.y - p.y) > 60 {
            armed = false
        }
        lastBundleId = focus.appBundleId
        if let o = originNow { lastFieldOrigin = o }

        // Indicador de presença: visível sempre que há um campo de texto válido
        // em foco (mesmo sem nada digitado), ancorado no canto da janela.
        let winRect = AXReader.windowFrame(for: focus.element) ?? (focus.elementRect ?? .zero)
        indicator.show(windowRect: winRect)

        // Contexto da tela (opt-in): classifica o app/página e dispara o OCR na
        // troca de contexto. Roda em background; não bloqueia a digitação.
        if SombraSettings.shared.useScreenContext {
            ScreenContext.shared.update(bundleId: focus.appBundleId,
                                        windowTitle: AXReader.windowTitle(for: focus.element))
        }

        // Ainda não digitou neste campo → apenas o ícone, sem sugestão de texto.
        guard armed else { dismissGhost(); return }

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

        // Fim da linha/texto? (nada depois do cursor na linha) → sombra à frente.
        // Senão (editando no meio), a sombra vai ABAIXO pra não cobrir o texto.
        lastAtEnd = atTextEnd || (focus.nextChar.map { $0 == "\n" || $0 == "\r" } ?? true)

        let prefix = focus.prefix
        guard prefix != lastPrefix else {
            // Mesmo prefixo: só reposiciona a sombra (cursor pode ter movido).
            if !currentSuffix.isEmpty {
                overlay.show(suffix: currentSuffix, caretRect: lastCaretRect,
                             elementRect: lastElementRect, isCorrection: mode == .correction,
                             atEnd: lastAtEnd)
            }
            return
        }
        lastPrefix = prefix

        // Atalho de emoji estilo ":nome" (Slack). Tem prioridade: se o fim do
        // texto for ":fel", sugere 😄 em vez de completar a palavra "fel".
        if let e = emojiShortcut(in: prefix) {
            showEmoji(trigger: e.trigger, emoji: e.emoji)
            return
        }

        // Agressivo: sugere já a partir do 1º caractere digitado no campo.
        guard prefix.count >= 1 else { dismissGhost(); return }

        // Comprimento da palavra parcial no fim do prefixo (0 = cursor numa
        // fronteira: o texto antes dele termina em espaço/pontuação).
        let partialWordLen = prefix.reversed().prefix { $0.isLetter || $0.isNumber }.count
        if partialWordLen == 0 {
            // Fronteira (após espaço/pontuação): sugere as PRÓXIMAS palavras.
            // Também aprende o par "palavra anterior → palavra recém-terminada".
            let s = SombraSettings.shared
            if s.personalizeEnabled, s.storeAllInputs, !s.isBlocked(lastBundleId) {
                WritingProfile.shared.observe(prefix: prefix)
            }
            requestPrediction(prefix: prefix)
        } else {
            // Dentro de uma palavra — já a partir da 1ª letra: completa a palavra
            // atual e segue a frase (a validação anti-lixo ocorre na resposta).
            requestPrediction(prefix: prefix)
        }
    }

    private func requestPrediction(prefix: String) {
        inFlight?.cancel()

        // Memória de frases: se VOCÊ costuma seguir esta palavra por outra (padrão
        // forte e dominante), oferece a SUA continuação direto — sem o modelo.
        if SombraSettings.shared.personalizeEnabled,
           !SombraSettings.shared.isBlocked(lastBundleId),
           let learned = WritingProfile.shared.learnedNextWord(for: prefix) {
            mode = .autocomplete
            correction = nil
            currentSuffix = learned
            overlay.show(suffix: learned, caretRect: lastCaretRect, elementRect: lastElementRect, atEnd: lastAtEnd)
            return
        }

        // MEIO DE PALAVRA: completa SÓ pelo dicionário do macOS — instantâneo e
        // SEM tocar na GPU. O modelo NÃO roda aqui; fica reservado para prever a
        // frase na fronteira (após o espaço). Resultado: completar palavra é
        // imediato, e a GPU/temperatura só sobem quando há de fato uma frase a
        // prever. Se o dicionário não conhece o começo (nome, termo técnico) mas
        // a palavra está "fechada" e errada, oferece correção; senão, nada.
        let endsLetterNow = prefix.last.map { $0.isLetter || $0.isNumber } ?? false
        if endsLetterNow {
            let partial = String(prefix.reversed().prefix { $0.isLetter }.reversed())
            if let comp = bestCompletion(forPartial: partial) {
                showAutocomplete(comp)
            } else if let fix = spellCorrectionForLastWord(in: prefix) {
                showCorrection(fix)
            } else {
                dismissGhost()
            }
            return
        }

        // FRONTEIRA (após espaço/pontuação): aqui sim o modelo prevê a próxima
        // frase. É a única situação em que a GPU é acionada.
        refreshBiasIfNeeded()
        // Contexto: tela (app/página + OCR, se ligado) + instrução do MODELO ativo
        // (modelDescription = nome do .gguf carregado) e prompts por app.
        let userCtx = SombraSettings.shared.effectiveContext(forApp: lastBundleId,
                                                              modelKey: modelDescription)
        let screenCtx = ScreenContext.shared.prompt
        let context = [screenCtx, userCtx].filter { !$0.isEmpty }.joined(separator: " ")
        let maxWords = SombraSettings.shared.suggestionWords
        inFlight = Task { [weak self] in
            guard let self else { return }
            let suffix = await self.predictor.predict(prefix: prefix, promptContext: context, maxWords: maxWords)
            if Task.isCancelled { return }
            await MainActor.run {
                // Só aplica se o prefixo ainda é o atual.
                guard self.lastPrefix == prefix else { return }

                // Relê a posição do cursor AGORA (a predição é assíncrona; o
                // cursor pode ter avançado) — evita a sombra aparecer "no meio".
                if let f = AXReader.read() {
                    self.lastCaretRect = f.caretRect
                    self.lastElementRect = f.elementRect
                }

                if let suffix, !suffix.isEmpty {
                    self.showAutocomplete(suffix)
                } else {
                    self.dismissGhost()
                }
            }
        }
    }

    /// Melhor completação para uma palavra começada, como SUFIXO a inserir.
    /// Entre as completações do dicionário, com a personalização ligada, prefere
    /// a que VOCÊ mais escreve (perfil); senão, a mais provável do dicionário.
    private func bestCompletion(forPartial partial: String) -> String? {
        let comps = SpellCorrector.completions(forPartialWord: partial)
        guard let first = comps.first else { return nil }
        let chosen = (SombraSettings.shared.personalizeEnabled
                      ? WritingProfile.shared.preferredCompletion(among: comps) : nil) ?? first
        let suffix = String(chosen.dropFirst(partial.count))
        return suffix.isEmpty ? nil : suffix
    }

    /// Se o fim do prefixo for um atalho de emoji (":nome" com 2+ letras), devolve
    /// o gatilho a apagar (":nome") e o emoji escolhido. nil caso contrário.
    private func emojiShortcut(in prefix: String) -> (trigger: String, emoji: String)? {
        guard SombraSettings.shared.emojiSuggestionsEnabled,
              let colon = prefix.lastIndex(of: ":") else { return nil }
        let query = prefix[prefix.index(after: colon)...]
        // 2+ caracteres de nome (letras/dígitos/underscore, como :raising_hand,
        // :100) após ":". O ":" deve INICIAR o token (começo, ou após espaço/
        // pontuação) — evita disparar em "http:", "12:30", "::", etc.
        guard query.count >= 2,
              query.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              query.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        if let before = prefix[..<colon].last, before.isLetter || before.isNumber { return nil }
        guard let emoji = EmojiCatalog.emoji(forQuery: String(query).lowercased()) else { return nil }
        return (":" + query, emoji)
    }

    private func showEmoji(trigger: String, emoji: String) {
        mode = .emoji
        correction = nil
        emojiReplace = (trigger, emoji)
        currentSuffix = emoji
        overlay.show(suffix: emoji, caretRect: lastCaretRect, elementRect: lastElementRect,
                     atEnd: lastAtEnd)
    }

    private func showAutocomplete(_ suffix: String) {
        mode = .autocomplete
        correction = nil
        emojiReplace = nil
        currentSuffix = suffix
        overlay.show(suffix: suffix, caretRect: lastCaretRect, elementRect: lastElementRect,
                     atEnd: lastAtEnd)
    }

    private func showCorrection(_ fix: (wrong: String, right: String)) {
        mode = .correction
        correction = fix
        currentSuffix = fix.right
        overlay.show(suffix: fix.right, caretRect: lastCaretRect,
                     elementRect: lastElementRect, isCorrection: true, atEnd: lastAtEnd)
    }

    // MARK: - Aceitar / descartar

    /// Chamado pelo KeyTap quando o Tab é pressionado.
    /// Aceita APENAS a próxima palavra; o restante da sombra permanece.
    /// Retorna true se havia algo a aceitar (e o Tab deve ser consumido).
    private func acceptIfPossible(whole: Bool = false) -> Bool {
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

        // Modo emoji: apaga o atalho digitado (":fel") e insere o emoji.
        if mode == .emoji, let e = emojiReplace {
            suppressUntil = Date().addingTimeInterval(0.2)
            overlay.hide()
            TextInjector.deleteBackward(count: e.trigger.count)
            TextInjector.insert(e.emoji)
            lastPrefix = String(lastPrefix.dropLast(e.trigger.count)) + e.emoji
            currentSuffix = ""
            emojiReplace = nil
            mode = .autocomplete
            return true
        }

        // Aceitar a FRASE INTEIRA de uma vez (atalho dedicado).
        if whole {
            var all = currentSuffix
            if lastPrefix.last == " " { while all.first == " " { all.removeFirst() } }
            guard !all.isEmpty else { return false }
            suppressUntil = Date().addingTimeInterval(0.2)
            overlay.hide()
            TextInjector.insert(all)
            lastPrefix += all
            currentSuffix = ""
            if SombraSettings.shared.personalizeEnabled, !SombraSettings.shared.isBlocked(lastBundleId) {
                WritingProfile.shared.record(all)
            }
            return true
        }

        var (word, rest) = Self.firstWord(currentSuffix)
        guard !word.isEmpty else { return false }

        // Normaliza o espaço inicial: no máximo UM, e ZERO se o texto antes do
        // cursor já termina em espaço. (Corrige o "dois espaços" ao aceitar.)
        let hadLeadingSpace = word.first == " "
        while word.first == " " { word.removeFirst() }
        if hadLeadingSpace, lastPrefix.last != " " { word = " " + word }
        guard !word.trimmingCharacters(in: .whitespaces).isEmpty else { return false }

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
                                  elementRect: self.lastElementRect, atEnd: self.lastAtEnd)
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
        emojiReplace = nil
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
