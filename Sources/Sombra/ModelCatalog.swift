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
    /// Modelos GGUF para Apple Silicon, do mais leve ao mais capaz (até ~2 GB).
    /// O usuário também pode importar qualquer .gguf manualmente.
    static let all: [CatalogModel] = [
        CatalogModel(
            name: "SmolLM2-135M-Instruct (Q8)",
            filename: "SmolLM2-135M-Instruct-Q8_0.gguf",
            url: "https://huggingface.co/unsloth/SmolLM2-135M-Instruct-GGUF/resolve/main/SmolLM2-135M-Instruct-Q8_0.gguf",
            approxMB: 145,
            summary: "Ultrarrápido. Completa palavras e trechos curtos. Sugestões simples.",
            hardware: "Qualquer Apple Silicon (M1+) · 8 GB RAM"
        ),
        CatalogModel(
            name: "SmolLM2-360M-Instruct (Q8) — base recomendada",
            filename: "SmolLM2-360M-Instruct-Q8_0.gguf",
            url: "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf",
            approxMB: 386,
            summary: "Equilíbrio leve. Frases curtas coerentes. Ótimo no dia a dia.",
            hardware: "Apple Silicon (M1+) · 8 GB RAM"
        ),
        CatalogModel(
            name: "Qwen2.5-0.5B-Instruct (Q8)",
            filename: "qwen2.5-0.5b-instruct-q8_0.gguf",
            url: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q8_0.gguf",
            approxMB: 644,
            summary: "Multilíngue e rápido. Bom para textos curtos em vários idiomas.",
            hardware: "Apple Silicon (M1+) · 8 GB RAM"
        ),
        CatalogModel(
            name: "Gemma 3 1B-it (Q4_K_M)",
            filename: "gemma-3-1b-it-Q4_K_M.gguf",
            url: "https://huggingface.co/unsloth/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf",
            approxMB: 806,
            summary: "Boa gramática e contexto. Sugestões mais ricas (um pouco mais lento).",
            hardware: "Apple Silicon (M1+) · 8–16 GB RAM"
        ),
        CatalogModel(
            name: "Qwen2.5-1.5B-Instruct (Q4_K_M)",
            filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            url: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            approxMB: 1065,
            summary: "Multilíngue mais capaz. Frases coerentes e contexto melhor.",
            hardware: "Apple Silicon (M1+) · 16 GB RAM"
        ),
        CatalogModel(
            name: "Llama-3.2-1B-Instruct (Q8)",
            filename: "Llama-3.2-1B-Instruct-Q8_0.gguf",
            url: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q8_0.gguf",
            approxMB: 1259,
            summary: "Bom em inglês e razoável em PT. Texto fluido para o tamanho.",
            hardware: "Apple Silicon (M1+) · 16 GB RAM"
        ),
        CatalogModel(
            name: "Llama-3.2-3B-Instruct (Q4_K_M)",
            filename: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            url: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            approxMB: 1925,
            summary: "Mais capaz. Sugestões ricas e bem contextualizadas. Mais lento.",
            hardware: "Apple Silicon M2/M3/M4 · 16 GB RAM"
        ),
        CatalogModel(
            name: "Qwen2.5-3B-Instruct (Q4_K_M)",
            filename: "qwen2.5-3b-instruct-q4_k_m.gguf",
            url: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf",
            approxMB: 2007,
            summary: "Forte multilíngue (PT/EN/ES…). As sugestões mais completas do catálogo.",
            hardware: "Apple Silicon M2/M3/M4 · 16 GB RAM"
        )
    ]
}
