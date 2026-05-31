import Foundation

/// Perfil local da escrita do usuário: contagem de palavras frequentes.
/// Usado para enviesar (logit bias) as sugestões a favor do seu vocabulário.
/// Fica em ~/Library/Application Support/Sombra/writing_profile.json.
@MainActor
final class WritingProfile {
    static let shared = WritingProfile()

    private var counts: [String: Int] = [:]
    // Memória de frases: palavra -> (palavra seguinte -> nº de vezes).
    // Captura padrões SEUS (nomes, jargão, assinaturas) que o modelo não conhece.
    private var bigrams: [String: [String: Int]] = [:]
    private var dirty = false
    private var lastSave = Date.distantPast
    private let maxWords = 5000
    // Evita inflar a contagem ao re-observar a mesma posição (ticks repetidos).
    private var lastObservedPair = ""

    private static var baseDir: URL {
        // modelsDir = .../Sombra/models  →  pai = .../Sombra
        ModelManager.modelsDir.deletingLastPathComponent()
    }
    private static var fileURL: URL { baseDir.appendingPathComponent("writing_profile.json") }
    private static var bigramURL: URL { baseDir.appendingPathComponent("writing_bigrams.json") }

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

    /// Observa o texto antes do cursor (numa fronteira de palavra) para aprender
    /// o par "palavra anterior → palavra recém-terminada". Idempotente por posição.
    func observe(prefix: String) {
        let words = Self.words(in: prefix)
        guard words.count >= 2 else { return }
        let prev = words[words.count - 2]
        let last = words[words.count - 1]
        guard prev.count >= 2, last.count >= 2 else { return }
        let key = prev + "\u{1}" + last
        guard key != lastObservedPair else { return }
        lastObservedPair = key
        bigrams[prev, default: [:]][last, default: 0] += 1
        counts[last, default: 0] += 1
        dirty = true
        saveThrottled()
    }

    /// Continuação aprendida (1 palavra) para o texto antes do cursor, se houver
    /// um padrão SEU forte o bastante: a última palavra já foi seguida por essa
    /// outra ao menos `minTotal` vezes e ela domina (≥50%). nil caso contrário.
    func learnedNextWord(for prefix: String, minTotal: Int = 3) -> String? {
        guard let last = Self.words(in: prefix).last, last.count >= 2,
              let nexts = bigrams[last] else { return nil }
        let total = nexts.values.reduce(0, +)
        guard total >= minTotal,
              let best = nexts.max(by: { $0.value < $1.value }),
              best.value * 2 >= total else { return nil }
        return best.key
    }

    /// Reinicia a sequência de observação (ao trocar de campo/app ou editar).
    func resetSequence() { lastObservedPair = "" }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map { $0.lowercased() }
    }

    func clear() {
        counts = [:]
        bigrams = [:]
        lastObservedPair = ""
        dirty = false
        try? FileManager.default.removeItem(at: Self.fileURL)
        try? FileManager.default.removeItem(at: Self.bigramURL)
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
        if let data = try? JSONEncoder().encode(bigrams) {
            try? data.write(to: Self.bigramURL)
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
        if let data = try? Data(contentsOf: Self.fileURL),
           let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
            counts = dict
        }
        if let data = try? Data(contentsOf: Self.bigramURL),
           let dict = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            bigrams = dict
        }
    }
}
