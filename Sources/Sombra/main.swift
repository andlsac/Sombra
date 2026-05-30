import AppKit

// Sombra — autocomplete com IA local para macOS.

// Modo de teste: `Sombra --selftest "texto a completar"`
// Carrega o modelo e imprime a previsão, sem abrir a UI. Útil para validar
// a inferência (llama.cpp + Metal) isoladamente.
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run(arguments: CommandLine.arguments)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar apenas
    app.run()
}
