# 👻 Sombra

Autocomplete + correção ortográfica com **IA local** para macOS, inspirado em
outros aplicativos do gênero. Lê o texto que você digita, prevê a continuação e
mostra num **bubble** à frente do cursor. Você aceita apertando **Tab**.

- 100% local e privado — Apple Silicon + **llama.cpp / Metal**
- Roda na **barra de menu** (sem ícone no Dock)
- Digitação fluida: event tap em **thread dedicada** + reaproveitamento de **KV-cache**

> **Status:** funcional. SmolLM2-360M embutido como base; catálogo de **8 modelos**
> (SmolLM2, Qwen2.5, Gemma 3, Llama 3.2 — até ~2 GB) para baixar pela GUI.

> **Sobre o projeto:** o código é aberto e **qualquer pessoa pode usar o app e o
> código** livremente. Foi pensado para **uso particular do autor**, não para uso
> geral/produção — pode conter arestas e decisões específicas. Eventualmente
> poderá receber **modificações no futuro**, sem qualquer compromisso de suporte.

## Recursos

- **Autocomplete palavra-por-palavra** — cada **Tab** insere só a próxima palavra;
  o resto continua como sombra.
- **Correção ortográfica** (NSSpellChecker, multilíngue) — quando não há
  autocomplete e a última palavra está errada, mostra a correção em **laranja**;
  o **Tab** substitui. Sem custo do modelo (instantâneo).
- **Edição no meio do texto** — sugere em qualquer fronteira de palavra, não só no
  fim da linha.
- **Bubble** ancorado à frente do cursor (com fallback abaixo do campo se o app
  não informa a posição do cursor; nunca sai da tela).

## Preferências (👻 na barra de menu → "Preferências…", ⌘,)

- **Modelo** — escolher o ativo (inclui a base embutida), **baixar** do catálogo
  (com tamanho, descrição e requisito de hardware), **importar** ou **apagar**
  `.gguf`. Modelos em `~/Library/Application Support/Sombra/models`.
- **Aparência** — nº de palavras por sugestão (1–10), cor e opacidade da sombra,
  remover ponto final, e o **emoji** do ícone na barra de menu.
- **Escrita** — lista de **prompts** (estilo/idioma) que dão contexto ao modelo,
  com sugestões prontas para adicionar.
- **Apps** — **bloquear apps** (não lê/sugere; ex.: gerenciadores de senha) e
  **prompts por app** (instruções específicas para email, navegador, mensagens…).

Na barra de menu também há **"Desativar neste app"**, para bloquear rapidamente o
app em foco.

## Requisitos

- macOS 14+ e **Apple Silicon** (M1–M4)
- Swift 6.x; CMake; clang (Command Line Tools ou Xcode)

## Setup completo

```bash
# 1. Compila o llama.cpp (lib + backends ggml, Metal embutido). Demora ~2-4 min.
./scripts/build_llama.sh

# 2. Baixa o modelo SmolLM2-360M-Instruct (GGUF Q8, ~369 MB).
./scripts/download_model.sh

# 3. Compila e empacota o app (inclui libs + modelo no .app).
./scripts/bundle.sh release    # ou: debug

open ./build/Sombra.app
```

### Teste rápido da inferência (sem UI)

```bash
DYLD_LIBRARY_PATH="$PWD/Frameworks" \
  "$(swift build --show-bin-path)/Sombra" --selftest "Bom dia, estou escrevendo para "
```

(No `.app` empacotado nem precisa do `DYLD_LIBRARY_PATH`.)

Para ver os logs em tempo real, rode o binário direto:

```bash
./build/Sombra.app/Contents/MacOS/Sombra
```

### Permissões (uma vez)

- **Acessibilidade** (obrigatória): Ajustes do Sistema → Privacidade e
  Segurança → Acessibilidade → ative a **Sombra**. Sem ela não há leitura de
  texto nem captura do Tab.

Como o app é assinado *ad-hoc*, ao atualizar o binário pode ser necessário
remover e reconceder a permissão de Acessibilidade.

## Arquitetura

| Componente | Arquivo | Papel |
|---|---|---|
| Entrada/menu bar | `main.swift`, `AppDelegate.swift`, `StatusBarController.swift` | App `.accessory`; toggle, status, "Desativar neste app" |
| Leitura de texto | `AXReader.swift` | Janela de texto perto do cursor + posição + app dono (Accessibility) |
| Captura do Tab | `KeyTap.swift` | `CGEventTap` em **thread dedicada**; consome o Tab via flag atômica |
| Bubble | `GhostOverlay.swift` | `NSPanel` à frente do cursor (cor configurável / laranja na correção) |
| Inserção | `TextInjector.swift` | Digita/substitui via CGEvent Unicode + Backspace (eventos marcados) |
| Orquestração | `SuggestionEngine.swift` | Loop orientado a evento: ler → prever → mostrar → aceitar |
| Inferência | `LlamaPredictor.swift`, `Sources/CLlama/` | Shim C sobre llama.cpp + KV-cache |
| Correção | `SpellCorrector.swift` | NSSpellChecker (multilíngue) da última palavra |
| Preferências/GUI | `SombraSettings.swift`, `SettingsView.swift`, `SettingsWindowController.swift` | Estado persistido (UserDefaults) + janela SwiftUI |
| Modelos | `ModelManager.swift`, `ModelCatalog.swift`, `ModelLocator.swift` | Baixar/importar/apagar/localizar `.gguf` |

### Fluxo

```
digitação (thread do tap, não bloqueia)
   → ao PAUSAR (~70 ms) → AXReader lê janela do texto + posição + app
   → app bloqueado? descarta. senão:
   → Predictor.predict() em background (KV-cache reutiliza o prefixo)
   → tem continuação?  bubble (autocomplete)
       senão  última palavra errada?  bubble laranja (correção)
   → Tab → consome → TextInjector insere a palavra (ou substitui na correção)
```

## Como a IA está integrada

- `Sources/CLlama/` — shim C fino sobre o `llama.cpp` (`sombra_load`,
  `sombra_complete`, `sombra_free`). Mantém ponteiros/batches/sampler em C e
  reaproveita o **KV-cache** entre chamadas (decodifica só os tokens novos).
- `LlamaPredictor.swift` — carrega o GGUF, serializa as chamadas (o contexto
  llama não é thread-safe), sampler **guloso** (continuação mais provável).
- `ModelLocator.swift` — acha o `.gguf` (modelo escolhido → pasta do usuário →
  env `SOMBRA_MODEL` → base embutida no `.app`).
- Metal compila os shaders em **runtime** (`GGML_METAL_EMBED_LIBRARY`), por isso
  funciona mesmo só com Command Line Tools.

## Fase 3 — otimização e recursos (próximo)

- [x] ~~**Reaproveitar KV-cache** entre teclas — decodifica só os tokens novos
      em vez do prefixo inteiro. Reduz a latência por tecla em prefixos longos
      (ex.: prompt de ~50 tokens: 401 ms → ~95 ms nas chamadas seguintes).~~
- [x] ~~**Correção ortográfica** da última palavra (NSSpellChecker, multilíngue).~~
- [x] ~~**Leitura/avaliação orientada a evento** (sem polling pesado na main thread).~~
- [x] ~~**Bloquear apps** e **prompts por app**.~~
- [x] ~~Preferências persistidas + GUI (modelo, cor, escrita, ícone).~~
- [ ] Modo **corretor gramatical de frase** (reescreve a frase, via chat template).
- [ ] Ajustar `maxTokens` por situação (palavra vs. frase) para snappier.
- [ ] Acompanhar fonte/tamanho do app alvo na sombra.
- [ ] Teardown limpo do Metal ao sair (hoje usa `_exit` no self-test).

### Por que llama.cpp (e não MLX)?

O MLX exige o compilador Metal do **Xcode completo** em tempo de build. O
llama.cpp compila os shaders Metal em **runtime**, então roda com apenas o
Command Line Tools — e entrega a mesma velocidade em modelos pequenos no M4.

## Licença

Código sob licença **MIT** — veja [LICENSE](LICENSE). © 2026 André Luís Alves Campos.

Créditos: a inferência usa o [llama.cpp](https://github.com/ggml-org/llama.cpp)
(MIT), baixado e compilado em build-time pelos scripts — não é redistribuído
neste repositório. Os modelos têm licenças próprias (Apache-2.0, Gemma, Llama,
Qwen) e são baixados pelo usuário.
