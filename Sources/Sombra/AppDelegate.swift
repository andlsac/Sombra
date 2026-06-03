import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var engine: SuggestionEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Permissões necessárias (Accessibility é obrigatória).
        Permissions.ensureAccessibility(prompt: true)

        // 2. Motor de sugestão (orquestra leitura -> previsão -> sombra).
        let engine = SuggestionEngine()
        self.engine = engine

        // 3. Menu bar com toggle on/off e status.
        self.statusBar = StatusBarController(engine: engine)

        // 4. Liga o loop.
        engine.start()

        // 5. Introdução na primeira abertura.
        if !SombraSettings.shared.hasSeenOnboarding {
            OnboardingWindowController.shared.show()
        } else if SombraSettings.shared.autoCheckUpdates {
            // 6. Verificação automática (só se o usuário optou). Silenciosa:
            //    abre a janela apenas se houver versão nova.
            UpdateWindowController.shared.checkAndPresent(userInitiated: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
        WritingProfile.shared.save()   // persiste o perfil antes de sair
        // O ggml-metal ABORTA nos destrutores estáticos ao encerrar o processo
        // (ggml_metal_rsets_free → ggml_abort → abort), causando o "crash" ao
        // fechar. Saímos direto, pulando o teardown do C++ — o SO recupera tudo.
        // (Mesmo motivo do _exit no --selftest.)
        fflush(nil)
        _exit(0)
    }
}
