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
            name: "Gemma 3 1B-it (Q4_K_M)",
            filename: "gemma-3-1b-it-Q4_K_M.gguf",
            url: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf",
            approxMB: 768,
            summary: L.t("Light and fluent. Good grammar for its size.",
                         "Leve e fluente. Boa gramática para o tamanho."),
            hardware: "Apple Silicon (M1+) · 8 GB RAM"
        ),
        CatalogModel(
            name: "Qwen3-1.7B (Q4_K_M)",
            filename: "Qwen3-1.7B-Q4_K_M.gguf",
            url: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
            approxMB: 1056,
            summary: L.t("Fast and strong multilingual writing. Great balance.",
                         "Rápido e forte multilíngue. Ótimo equilíbrio."),
            hardware: "Apple Silicon (M1+) · 16 GB RAM"
        ),
        CatalogModel(
            name: L.t("Gemma 4 E2B (i1-Q4_K_M) — recommended",
                      "Gemma 4 E2B (i1-Q4_K_M) — recomendado"),
            filename: "gemma-4-E2B.i1-Q4_K_M.gguf",
            url: "https://huggingface.co/mradermacher/gemma-4-E2B-i1-GGUF/resolve/main/gemma-4-E2B.i1-Q4_K_M.gguf",
            approxMB: 3200,
            summary: L.t("~2B effective params (fast despite size). Rich, coherent text — the main model.",
                         "~2B de params efetivos (rápido apesar do tamanho). Texto rico e coerente — o modelo principal."),
            hardware: "Apple Silicon (M1+) · 16 GB RAM"
        ),
        CatalogModel(
            name: "Qwen3-4B (Q4_K_M)",
            filename: "Qwen3-4B-Q4_K_M.gguf",
            url: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
            approxMB: 2381,
            summary: L.t("The most capable here. Best context and writing. Needs more RAM/CPU.",
                         "O mais capaz daqui. Melhor contexto e escrita. Exige mais RAM/CPU."),
            hardware: "Apple Silicon M2/M3/M4 · 16 GB RAM"
        )
    ]
}
