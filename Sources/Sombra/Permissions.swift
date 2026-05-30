import AppKit
import ApplicationServices

enum Permissions {
    /// Verifica (e opcionalmente solicita) a permissão de Acessibilidade.
    /// Sem ela não conseguimos ler o texto focado nem interceptar o Tab.
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            NSLog("[Sombra] Acessibilidade NÃO concedida. Ative em Ajustes do Sistema > Privacidade e Segurança > Acessibilidade.")
        }
        return trusted
    }

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Permissão de gravação de tela (necessária para o OCR de contexto).
    /// Não bloqueia o app; o OCR simplesmente fica vazio até ser concedida.
    static func ensureScreenRecording() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }
}
