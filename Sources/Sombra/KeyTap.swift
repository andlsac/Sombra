import AppKit
import CoreGraphics

/// Intercepta o teclado globalmente numa THREAD DEDICADA, para que a digitação
/// nunca espere pela main thread (onde rodam leituras de Acessibilidade e UI).
///  - captura o TAB e aceita a sugestão (consumindo o evento);
///  - notifica qualquer outra tecla para recalcular/descartar a sombra.
/// Os callbacks são chamados NA THREAD DO TAP — devem ser leves e despachar
/// qualquer trabalho de UI/estado para a main queue.
final class KeyTap {
    /// Retorna true se o Tab deve ser consumido (havia sugestão). Síncrono e leve.
    var onTab: (() -> Bool)?
    /// Aceitar a sugestão INTEIRA de uma vez. Retorna true se consumiu.
    var onAcceptAll: (() -> Bool)?
    /// Chamado em qualquer keyDown que não seja um dos atalhos de aceitar.
    var onOtherKey: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?

    // Atalho de aceitar (configurável). Padrão: Tab (keycode 48, sem modificadores).
    // Atualizados pela main thread; lidos no callback do tap (leitura de Int é benigna).
    var acceptKeyCode: CGKeyCode = 48
    var acceptModifiers: Int = 0  // bitmask 1=⌘ 2=⌥ 4=⌃ 8=⇧
    var acceptAllKeyCode: CGKeyCode = 48
    var acceptAllModifiers: Int = 8 // ⇧Tab

    /// Converte os flags de um CGEvent para o nosso bitmask de modificadores.
    private static func modMask(_ flags: CGEventFlags) -> Int {
        var m = 0
        if flags.contains(.maskCommand) { m |= 1 }
        if flags.contains(.maskAlternate) { m |= 2 }
        if flags.contains(.maskControl) { m |= 4 }
        if flags.contains(.maskShift) { m |= 8 }
        return m
    }

    func start() {
        let t = Thread { [weak self] in
            guard let self else { return }
            self.threadRunLoop = CFRunLoopGetCurrent()
            self.installTap()
            CFRunLoopRun()
        }
        t.name = "com.sombra.keytap"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    private func installTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                // Reativa o tap se o sistema o desabilitar (timeout/userInput).
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon {
                        let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
                        if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()

                // Ignora os keystrokes que nós mesmos injetamos (texto aceito).
                if event.getIntegerValueField(.eventSourceUserData) == TextInjector.injectionTag {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let mods = KeyTap.modMask(event.flags)
                if keyCode == me.acceptKeyCode && mods == me.acceptModifiers {
                    if me.onTab?() == true { return nil } // consome o atalho ao aceitar (palavra)
                    return Unmanaged.passUnretained(event)
                }
                if keyCode == me.acceptAllKeyCode && mods == me.acceptAllModifiers {
                    if me.onAcceptAll?() == true { return nil } // consome ao aceitar TUDO
                    return Unmanaged.passUnretained(event)
                }

                me.onOtherKey?()
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            NSLog("[Sombra] Falha ao criar event tap (Acessibilidade concedida?).")
            return
        }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource, let rl = threadRunLoop {
            CFRunLoopRemoveSource(rl, src, .commonModes)
        }
        if let rl = threadRunLoop { CFRunLoopStop(rl) }
        tap = nil
        runLoopSource = nil
        threadRunLoop = nil
        thread = nil
    }
}
