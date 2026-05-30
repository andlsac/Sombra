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
    /// Chamado em qualquer keyDown que não seja Tab.
    var onOtherKey: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?

    private let kVK_Tab: CGKeyCode = 48

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
                if keyCode == me.kVK_Tab {
                    if me.onTab?() == true { return nil } // consome o Tab
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
