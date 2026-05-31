import Foundation

/// Um modelo conhecido que a GUI pode baixar.
struct CatalogModel: Identifiable, Hashable {
    var id: String { filename }
    let name: String
    let filename: String
    let url: String
    let approxMB: Int
    /// O que ele faz bem (linguagem simples).
    let summary: String
    /// Requisito de hardware sugerido (simples e direto).
    let hardware: String
}

enum ModelCatalog {
    /// Modelos GGUF **base** (continuação pura) para Apple Silicon, do mais leve
    /// ao mais capaz. Base — e não "instruct"/chat — porque a tarefa é autocomplete:
    /// o modelo deve CONTINUAR o seu texto, nunca "responder" como assistente.
    /// O usuário também pode importar qualquer .gguf manualmente.
    /// Textos localizados (seguem o idioma do sistema).
    static let all: [CatalogModel] = [
        CatalogModel(
            name: "SmolLM2-135M base (Q8)",
            filename: "SmolLM2-135M.Q8_0.gguf",
            url: "https://huggingface.co/QuantFactory/SmolLM2-135M-GGUF/resolve/main/SmolLM2-135M.Q8_0.gguf",
            approxMB: 138,
            summary: L.t("Tiniest model. Instant; completes words and very short snippets.",
                         "O menor modelo. Instantâneo; completa palavras e trechos curtíssimos."),
            hardware: L.t("Any Apple Silicon (M1+) · 8 GB RAM", "Qualquer Apple Silicon (M1+) · 8 GB RAM")
        ),
        CatalogModel(
            name: "SmolLM2-360M base (Q8)",
            filename: "SmolLM2-360M.Q8_0.gguf",
            url: "https://huggingface.co/QuantFactory/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            approxMB: 368,
            summary: L.t("Ultra-light. Pure continuation; simple suggestions, very fast.",
                         "Ultraleve. Continuação pura; sugestões simples e muito rápidas."),
            hardware: "Apple Silicon (M1+) · 8 GB RAM"
        ),
        CatalogModel(
            name: L.t("Qwen2.5-0.5B base (Q8) — recommended",
                      "Qwen2.5-0.5B base (Q8) — recomendado"),
            filename: "Qwen2.5-0.5B.Q8_0.gguf",
            url: "https://huggingface.co/QuantFactory/Qwen2.5-0.5B-GGUF/resolve/main/Qwen2.5-0.5B.Q8_0.gguf",
            approxMB: 506,
            summary: L.t("Best balance of speed and quality. Multilingual, natural autocomplete.",
                         "Melhor equilíbrio entre velocidade e qualidade. Multilíngue, autocomplete natural."),
            hardware: "Apple Silicon (M1+) · 8 GB RAM"
        ),
        CatalogModel(
            name: "Qwen2.5-1.5B base (Q4_K_M)",
            filename: "Qwen2.5-1.5B.Q4_K_M.gguf",
            url: "https://huggingface.co/QuantFactory/Qwen2.5-1.5B-GGUF/resolve/main/Qwen2.5-1.5B.Q4_K_M.gguf",
            approxMB: 940,
            summary: L.t("Richer, more coherent continuations. Great context (a bit slower).",
                         "Continuações mais ricas e coerentes. Ótimo contexto (um pouco mais lento)."),
            hardware: "Apple Silicon (M1+) · 16 GB RAM"
        ),
        CatalogModel(
            name: "Qwen2.5-3B base (Q4_K_M)",
            filename: "Qwen2.5-3B.Q4_K_M.gguf",
            url: "https://huggingface.co/QuantFactory/Qwen2.5-3B-GGUF/resolve/main/Qwen2.5-3B.Q4_K_M.gguf",
            approxMB: 1840,
            summary: L.t("The most capable here. Strong multilingual writing. Needs more RAM/CPU.",
                         "O mais capaz daqui. Escrita multilíngue forte. Exige mais RAM/CPU."),
            hardware: "Apple Silicon M2/M3/M4 · 16 GB RAM"
        )
    ]
}
