import AppKit

// Sombra — autocomplete com IA local para macOS.

// Modo de teste: `Sombra --selftest "texto a completar"`
// Carrega o modelo e imprime a previsão, sem abrir a UI. Útil para validar
// a inferência (llama.cpp + Metal) isoladamente.
if CommandLine.arguments.contains("--selftest") {
    SelfTest.run(arguments: CommandLine.arguments)
} else if CommandLine.arguments.contains("--worddict") {
    // Valida o dicionário embutido (completação por frequência) sem UI/modelo.
    WordDictionaryTest.run(arguments: CommandLine.arguments)
} else if CommandLine.arguments.contains("--leque") {
    // Valida o "leque" de candidatos do modelo (completação com contexto).
    LequeTest.run(arguments: CommandLine.arguments)
} else if CommandLine.arguments.contains("--rank") {
    // Valida "dicionário + ranqueio do modelo" (o conserto do corte de letras).
    RankTest.run(arguments: CommandLine.arguments)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar apenas
    app.run()
}
