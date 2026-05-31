import AppKit
import ApplicationServices

/// Snapshot do campo de texto focado no momento.
struct FocusedText {
    let element: AXUIElement
    let length: Int          // total de caracteres (-1 se desconhecido)
    let caret: Int           // posição do cursor (UTF-16)
    let prefix: String       // janela de texto antes do cursor
    let nextChar: Character? // caractere logo após o cursor (nil = fim)
    let caretRect: CGRect?   // retângulo do cursor (coords de tela, top-left)
    let elementRect: CGRect? // frame do campo focado (fallback de ancoragem)
    let appBundleId: String? // bundle id do app dono do campo (ex.: com.apple.Safari)
}

/// Lê o campo de texto focado via Accessibility API. Para evitar travar a
/// digitação em textos grandes, lê apenas uma janela de caracteres perto do
/// cursor (não o valor inteiro), com fallback para o valor completo.
enum AXReader {
    private static let systemWide = AXUIElementCreateSystemWide()
    private static let windowChars = 800
    private static var electronEnabledPids = Set<pid_t>()

    /// Liga a árvore de acessibilidade de apps Chromium/Electron (Claude, VS Code,
    /// Slack…), que por padrão não expõem o texto, setando `AXManualAccessibility`
    /// no app. Feito uma vez por app; em apps nativos é um no-op inofensivo.
    static func enableElectronAX(_ element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return }
        if electronEnabledPids.contains(pid) { return }
        electronEnabledPids.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func focusedTextField() -> AXUIElement? {
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        )
        guard err == .success, let f = focused else { return nil }
        return (f as! AXUIElement)
    }

    static func read() -> FocusedText? {
        guard let element = focusedTextField() else { return nil }
        guard let caret = selectedCaret(element) else {
            // Campo focado existe mas não expõe a posição do cursor: típico de
            // apps Chromium/Electron (Claude, VS Code, Slack…). Liga a árvore
            // de acessibilidade deles; os próximos ticks já devem conseguir ler.
            enableElectronAX(element)
            return nil
        }

        // Só sugere em campos de TEXTO EDITÁVEIS. Evita disparar em barra de
        // URL, caixas de busca, rótulos (AXStaticText) e elementos quaisquer
        // de páginas web — causa comum de "sugere em qualquer lugar" no navegador.
        guard isEditableTextElement(element) else { return nil }

        var length = numberOfCharacters(element) ?? -1
        var prefix: String?
        var nextChar: Character?

        // Caminho rápido: só a janela [caret-N, caret] via string-for-range.
        let start = max(0, caret - windowChars)
        let winLen = caret - start
        if winLen == 0 {
            prefix = ""
        } else if let s = stringForRange(element, location: start, length: winLen) {
            prefix = s
        }

        // Fallback: valor completo (apps que não suportam string-for-range).
        if prefix == nil || length < 0 {
            if let full = value(element) {
                let ns = full as NSString
                if length < 0 { length = ns.length }
                if caret >= 0 && caret <= ns.length {
                    let s0 = max(0, caret - windowChars)
                    prefix = ns.substring(with: NSRange(location: s0, length: caret - s0))
                    if caret < ns.length, let sc = UnicodeScalar(ns.character(at: caret)) {
                        nextChar = Character(sc)
                    }
                }
            }
        }
        guard let pfx = prefix else { enableElectronAX(element); return nil }

        // Caractere após o cursor (para detectar fronteira de palavra).
        if nextChar == nil, length >= 0, caret < length,
           let s = stringForRange(element, location: caret, length: 1) {
            nextChar = s.first
        }

        return FocusedText(
            element: element,
            length: length,
            caret: caret,
            prefix: pfx,
            nextChar: nextChar,
            caretRect: caretRect(for: element, location: caret),
            elementRect: elementRect(for: element),
            appBundleId: bundleId(for: element)
        )
    }

    /// true se o elemento focado é um campo de texto onde faz sentido sugerir.
    /// Aceita os papéis editáveis (TextField, TextArea, ComboBox) e rejeita
    /// campos de busca e de senha (subrole), que não devem receber autocomplete.
    private static func isEditableTextElement(_ element: AXUIElement) -> Bool {
        let role = stringAttr(element, kAXRoleAttribute)
        let subrole = stringAttr(element, kAXSubroleAttribute)

        // Nunca em campos de busca ou senha.
        if subrole == kAXSearchFieldSubrole || subrole == kAXSecureTextFieldSubrole {
            return false
        }
        switch role {
        case kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole: return true
        default: return false
        }
    }

    private static func stringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    /// Bundle id do app que possui o elemento focado.
    static func bundleId(for element: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    // MARK: - Leituras individuais

    private static func selectedCaret(_ element: AXUIElement) -> Int? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rv = rangeRef else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue((rv as! AXValue), .cfRange, &range) else { return nil }
        return range.location >= 0 ? range.location : nil
    }

    private static func numberOfCharacters(_ element: AXUIElement) -> Int? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &v) == .success,
              let n = v as? Int else { return nil }
        return n
    }

    private static func value(_ element: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func stringForRange(_ element: AXUIElement, location: Int, length: Int) -> String? {
        guard location >= 0, length >= 0 else { return nil }
        var r = CFRange(location: location, length: length)
        guard let axr = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, axr, &out
        )
        guard err == .success, let s = out as? String else { return nil }
        return s
    }

    /// Retângulo de tela do cursor, para posicionar a sombra.
    static func caretRect(for element: AXUIElement, location: Int) -> CGRect? {
        var cfRange = CFRange(location: max(0, location), length: 0)
        guard let axRange = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var boundsRef: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &boundsRef
        )
        guard err == .success, let b = boundsRef else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue((b as! AXValue), .cgRect, &rect) else { return nil }
        return rect
    }

    /// Frame do elemento focado (posição + tamanho), em coords de tela (top-left).
    static func elementRect(for element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let p = posRef, let s = sizeRef else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue((p as! AXValue), .cgPoint, &origin),
              AXValueGetValue((s as! AXValue), .cgSize, &size) else { return nil }
        let r = CGRect(origin: origin, size: size)
        return r.isEmpty ? nil : r
    }
}
