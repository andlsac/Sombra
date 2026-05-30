import AppKit
import CoreGraphics

/// Insere texto no app focado simulando digitação Unicode.
/// Funciona na maioria dos apps porque não depende do layout do teclado.
enum TextInjector {
    /// Marca posta em `eventSourceUserData` para o nosso event tap reconhecer
    /// (e ignorar) os keystrokes que nós mesmos injetamos.
    static let injectionTag: Int64 = 0x536F6D6272 // "Sombr"

    /// Apaga `count` caracteres à esquerda do cursor (tecla Backspace).
    static func deleteBackward(count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        let kVK_Delete: CGKeyCode = 51
        for _ in 0..<count {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: kVK_Delete, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: kVK_Delete, keyDown: false)
            else { continue }
            down.setIntegerValueField(.eventSourceUserData, value: injectionTag)
            up.setIntegerValueField(.eventSourceUserData, value: injectionTag)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .combinedSessionState)

        for scalarChunk in text.unicodeScalarChunks(maxLength: 20) {
            var utf16 = Array(scalarChunk.utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.setIntegerValueField(.eventSourceUserData, value: injectionTag)
            up.setIntegerValueField(.eventSourceUserData, value: injectionTag)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }
}

private extension String {
    /// Quebra a string em pedaços (CGEvent tem limite prático por evento).
    func unicodeScalarChunks(maxLength: Int) -> [String] {
        guard count > maxLength else { return [self] }
        var chunks: [String] = []
        var current = ""
        for ch in self {
            current.append(ch)
            if current.count >= maxLength {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
