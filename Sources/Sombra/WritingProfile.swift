import Foundation

/// Perfil local da escrita do usuário: contagem de palavras frequentes.
/// Usado para enviesar (logit bias) as sugestões a favor do seu vocabulário.
/// Fica em ~/Library/Application Support/Sombra/writing_profile.json.
@MainActor
final class WritingProfile {
    static let shared = WritingProfile()

    private var counts: [String: Int] = [:]
    private var dirty = false
    private var lastSave = Date.distantPast
    private let maxWords = 5000

    private static var fileURL: URL {
        // modelsDir = .../Sombra/models  →  pai = .../Sombra
        ModelManager.modelsDir.deletingLastPathComponent()
            .appendingPathComponent("writing_profile.json")
    }

    init() { load() }

    var wordCount: Int { counts.count }

    /// Registra as palavras (>=3 letras) de um trecho de texto.
    func record(_ text: String) {
        var changed = false
        for raw in text.split(whereSeparator: { !$0.isLetter && $0 != "'" }) {
            let w = raw.lowercased()
            if w.count >= 3 {
                counts[w, default: 0] += 1
                changed = true
            }
        }
        if changed { dirty = true; saveThrottled() }
    }

    /// Palavras mais frequentes (acima de `minCount`), até `limit`.
    func topWords(limit: Int = 150, minCount: Int = 2) -> [String] {
        counts.filter { $0.value >= minCount }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    func clear() {
        counts = [:]
        dirty = false
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    // MARK: - Persistência

    private func saveThrottled() {
        guard Date().timeIntervalSince(lastSave) > 5 else { return }
        save()
    }

    func save() {
        guard dirty else { return }
        pruneIfNeeded()
        if let data = try? JSONEncoder().encode(counts) {
            try? data.write(to: Self.fileURL)
        }
        dirty = false
        lastSave = Date()
    }

    private func pruneIfNeeded() {
        guard counts.count > maxWords else { return }
        let keep = counts.sorted { $0.value > $1.value }.prefix(maxWords)
        counts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data) else { return }
        counts = dict
    }
}
