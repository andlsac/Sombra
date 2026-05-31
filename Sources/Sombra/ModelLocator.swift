import Foundation

/// Descobre onde está o arquivo .gguf do modelo.
/// Ordem: variável de ambiente → dentro do .app → pasta models/ do projeto.
enum ModelLocator {
    static let fileName = "Qwen2.5-0.5B.Q8_0.gguf"

    static func find() -> String? {
        let fm = FileManager.default

        // 0) Modelo escolhido na GUI (Preferências).
        let chosen = SombraSettings.shared.modelPath
        if !chosen.isEmpty, fm.fileExists(atPath: chosen) {
            return chosen
        }

        // 0.5) Primeiro .gguf na pasta de modelos do usuário (Application Support).
        if let first = (try? fm.contentsOfDirectory(at: ModelManager.modelsDir,
                                                     includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension.lowercased() == "gguf" }) {
            return first.path
        }

        // 1) Override explícito por variável de ambiente.
        if let env = ProcessInfo.processInfo.environment["SOMBRA_MODEL"],
           fm.fileExists(atPath: env) {
            return env
        }

        // 2) Empacotado no .app (Contents/Resources/models/…).
        if let res = Bundle.main.resourceURL?
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(fileName) {
            if fm.fileExists(atPath: res.path) { return res.path }
        }

        // 3) Pasta models/ ao lado da árvore do projeto (modo dev).
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        var dir: URL? = exe.deletingLastPathComponent()
        for _ in 0..<8 {
            guard let d = dir else { break }
            let candidate = d.appendingPathComponent("models").appendingPathComponent(fileName)
            if fm.fileExists(atPath: candidate.path) { return candidate.path }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }
}
