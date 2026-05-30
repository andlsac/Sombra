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
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
    }
}
