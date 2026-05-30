import Foundation

/// Contrato do preditor. A Fase 2 troca o `HeuristicPredictor`
/// por um `MLXPredictor` (SmolLM2 / Gemma) mantendo esta interface.
protocol Predictor: AnyObject {
    /// Dado o texto antes do cursor e o contexto de prompt (instruções gerais +
    /// do app atual), retorna o sufixo previsto, ou nil.
    /// Deve ser cancelável e rodar fora do main thread.
    func predict(prefix: String, promptContext: String) async -> String?
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

    func predict(prefix: String, promptContext: String) async -> String? {
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
