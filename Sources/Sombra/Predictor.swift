import Foundation

/// Contrato do preditor. A Fase 2 troca o `HeuristicPredictor`
/// por um `MLXPredictor` (SmolLM2 / Gemma) mantendo esta interface.
protocol Predictor: AnyObject {
    /// Dado o texto antes do cursor e o contexto de prompt (instruções gerais +
    /// do app atual), retorna o sufixo previsto, ou nil. `maxWords` limita o
    /// tamanho (no meio da palavra usamos poucas palavras → geração rápida que
    /// aparece já enquanto você digita).
    /// Deve ser cancelável e rodar fora do main thread.
    func predict(prefix: String, promptContext: String, maxWords: Int) async -> String?

    /// "Leque": vários candidatos de continuação para o MESMO contexto, em ordem
    /// de probabilidade. Usado para completar com contexto a partir das letras
    /// digitadas (o motor filtra o leque pelo prefixo). Cancelável; fora da main.
    /// `count` = quantos candidatos; `maxWords` = tamanho de cada um.
    func candidates(prefix: String, promptContext: String, count: Int, maxWords: Int) async -> [String]

    /// Reordena `candidates` (palavras inteiras já começando com o que foi
    /// digitado) pela probabilidade do MODELO no contexto. O dicionário garante
    /// as letras certas; o modelo escolhe a que cabe na frase. `contextPrefix` =
    /// texto antes da palavra (sem a parcial). Cancelável; fora da main.
    func rank(candidates: [String], contextPrefix: String, promptContext: String) async -> [String]

    /// Personalização: favorece as palavras dadas com um bônus em logits.
    /// `strength` <= 0 ou lista vazia remove o viés.
    func setBias(words: [String], strength: Float)

    /// Temperatura de amostragem (0 = greedy/determinístico; >0 = mais natural).
    func setTemperature(_ temperature: Double)
}

extension Predictor {
    // Padrão: sem personalização nem temperatura (ex.: HeuristicPredictor).
    func setBias(words: [String], strength: Float) {}
    func setTemperature(_ temperature: Double) {}
    // Padrão: sem leque (o HeuristicPredictor não gera candidatos de IA; nesse
    // caso o motor usa o dicionário/heurística como fallback).
    func candidates(prefix: String, promptContext: String, count: Int, maxWords: Int) async -> [String] { [] }
    // Padrão: sem ranqueio por modelo → devolve a ordem original (do dicionário).
    func rank(candidates: [String], contextPrefix: String, promptContext: String) async -> [String] { candidates }
}

/// Placeholder determinístico para validar o loop ponta-a-ponta.
/// NÃO é IA — apenas completa a palavra atual / continuações comuns.
/// Será substituído pelo MLXPredictor na Fase 2.
final class HeuristicPredictor: Predictor {
    // Pequeno dicionário de continuações frequentes (PT/EN) só para demo.
    private let phrases: [String: String] = [
        "muito obrig": "ado pela atenção",
        "por favor": ", me avise se precisar de algo",
        "bom dia": ", tudo bem?",
        "atenciosa": "mente,",
        "fico no agu": "ardo do seu retorno",
        "thank you": " for your time",
        "best reg": "ards,",
        "looking forward": " to hearing from you",
        "let me kn": "ow if you have any questions"
    ]

    private let words = [
        "obrigado", "obrigada", "atenciosamente", "cordialmente",
        "informações", "disponível", "retorno", "documento", "reunião",
        "available", "information", "regarding", "schedule", "document"
    ]

    func predict(prefix: String, promptContext: String, maxWords: Int) async -> String? {
        let lower = prefix.lowercased()
        guard !lower.isEmpty else { return nil }

        // 1) Continuação de frase conhecida.
        for (key, completion) in phrases where lower.hasSuffix(key) {
            return completion
        }

        // 2) Completar a palavra atual a partir do dicionário.
        if let lastWord = lower.split(whereSeparator: { $0 == " " || $0 == "\n" }).last,
           lastWord.count >= 3 {
            for w in words where w.hasPrefix(String(lastWord)) && w.count > lastWord.count {
                return String(w.dropFirst(lastWord.count))
            }
        }
        return nil
    }
}
