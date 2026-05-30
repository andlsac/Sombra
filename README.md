# 👻 Sombra

**Local-AI autocomplete + spell-correction for macOS.** Runs 100% on your Mac
(Apple Silicon, `llama.cpp` + Metal), lives in the menu bar, accept with **Tab**.

🇬🇧 [English](#english) · 🇧🇷 [Português](#português)

---

<a name="english"></a>
## English

Sombra predicts the continuation of what you're typing and shows it in a **bubble
in front of the cursor** — press **Tab** to accept. It also fixes the spelling of
the last word. Inspired by other apps of the genre.

> **This is a personal project.** Anyone is free to use the app and the code. It
> was built for the **author's own everyday use** — not for general/production
> use — so it may have rough edges and opinionated choices. It may receive
> **changes in the future**, with no commitment to support or stability.

### 🔒 Privacy — it stays on your machine

- Inference is **100% local** (`llama.cpp` + Metal). No cloud, no telemetry.
- Sombra makes **no network connections during normal use** — it does not phone
  home.
- The **only** moment it touches the internet is when **you** press **Download**
  for a model in Preferences (files come from Hugging Face).
- **Don't take my word for it:** the code is open — audit it. If you'd rather be
  sure, block all of Sombra's connections with a firewall such as
  **[LuLu](https://objective-see.org/products/lulu.html)** (free & open-source),
  **Little Snitch** or **Radio Silence**. Autocomplete and correction keep working
  fully offline — you just won't be able to download new models in-app (you can
  still drop `.gguf` files into the models folder manually).

### Features

- **Word-by-word autocomplete** — each **Tab** inserts only the next word.
- **Spell correction** of the last word (native macOS spell-checker, multilingual)
  — shown in **orange**; Tab replaces the misspelled word.
- **Mid-text editing** — suggests at any word boundary, not just at the line end.
- **Per-app rules** — block apps (e.g. password managers) and set **per-app
  prompts** (email, browser, messaging…).
- Configurable: suggestion length, bubble color/opacity, menu-bar icon.
- **8-model catalog** to download (SmolLM2, Qwen2.5, Gemma 3, Llama 3.2 — up to
  ~2 GB), or import any `.gguf`.

### Requirements

- macOS 14+ and **Apple Silicon** (M1–M4)
- To build: Swift, CMake, clang (Command Line Tools or full Xcode)

### Build & run

```bash
./scripts/build_llama.sh      # build llama.cpp (libs + Metal), ~2-4 min
./scripts/download_model.sh   # download the base model (~369 MB)
./scripts/bundle.sh release   # build & package Sombra.app (model embedded)
open ./build/Sombra.app
```

Grant **Accessibility** (System Settings → Privacy & Security → Accessibility →
Sombra). That is the only permission required.

### ☕ Support

If Sombra is useful to you and you'd like to support it — totally optional:

- ☕ **Ko-fi:** https://ko-fi.com/andre38264
- 💳 **PayPal:** https://www.paypal.com/donate/?business=FF3HTRZWDV8HS&no_recurring=0&item_name=Hey+you+%3AD&currency_code=EUR
- 🇧🇷 **Pix (Brazil):** `37adbd1c-6e5e-4d2f-916a-04bc892fe496`

### License

MIT — see [LICENSE](LICENSE). © 2026 André Luís Alves Campos. Inference uses
[llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT), fetched and built at
build time (not redistributed here). Models have their own licenses and are
downloaded by the user.

---

<a name="português"></a>
## Português

Autocomplete + correção ortográfica com **IA local** para macOS, inspirado em
outros aplicativos do gênero. Lê o texto que você digita, prevê a continuação e
mostra num **bubble** à frente do cursor. Você aceita apertando **Tab**.

- 100% local e privado — Apple Silicon + **llama.cpp / Metal**
- Roda na **barra de menu** (sem ícone no Dock)
- Digitação fluida: event tap em **thread dedicada** + reaproveitamento de **KV-cache**

> **Sobre o projeto:** o código é aberto e **qualquer pessoa pode usar o app e o
> código** livremente. Foi pensado para **uso particular do autor**, não para uso
> geral/produção — pode conter arestas e decisões específicas. Eventualmente
> poderá receber **modificações no futuro**, sem qualquer compromisso de suporte.

### 🔒 Privacidade — fica tudo na sua máquina

- A inferência é **100% local** (`llama.cpp` + Metal). Sem nuvem, sem telemetria.
- A Sombra **não faz nenhuma conexão de rede no uso normal** — não "liga pra casa".
- A **única** vez que acessa a internet é quando **você** clica em **Baixar** um
  modelo nas Preferências (arquivos vêm do Hugging Face).
- **Não precisa confiar na minha palavra:** o código é aberto — verifique. Se
  preferir garantir, bloqueie todas as conexões da Sombra com um firewall como
  **[LuLu](https://objective-see.org/products/lulu.html)** (grátis e
  open-source), **Little Snitch** ou **Radio Silence**. O autocomplete e a
  correção continuam funcionando **offline** — você só não conseguirá baixar
  modelos pelo app (mas pode colocar arquivos `.gguf` na pasta manualmente).

### Recursos

- **Autocomplete palavra-por-palavra** — cada **Tab** insere só a próxima palavra.
- **Correção ortográfica** (NSSpellChecker, multilíngue) — quando não há
  autocomplete e a última palavra está errada, mostra a correção em **laranja**;
  o **Tab** substitui. Sem custo do modelo (instantâneo).
- **Edição no meio do texto** — sugere em qualquer fronteira de palavra.
- **Bubble** à frente do cursor (com fallback abaixo do campo; nunca sai da tela).

### Preferências (👻 na barra de menu → "Preferências…", ⌘,)

- **Modelo** — escolher o ativo (inclui a base embutida), **baixar** do catálogo
  (com tamanho, descrição e requisito de hardware), **importar** ou **apagar**
  `.gguf`. Modelos em `~/Library/Application Support/Sombra/models`.
- **Aparência** — nº de palavras por sugestão (1–10), cor e opacidade da sombra,
  remover ponto final, e o **emoji** do ícone na barra de menu.
- **Escrita** — lista de **prompts** (estilo/idioma) que dão contexto ao modelo,
  com sugestões prontas.
- **Apps** — **bloquear apps** (não lê/sugere) e **prompts por app**.

Na barra de menu também há **"Desativar neste app"**, para bloquear rapidamente o
app em foco.

### Requisitos

- macOS 14+ e **Apple Silicon** (M1–M4)
- Para compilar: Swift, CMake, clang (Command Line Tools ou Xcode)

### Setup completo

```bash
./scripts/build_llama.sh      # compila o llama.cpp (libs + Metal), ~2-4 min
./scripts/download_model.sh   # baixa o modelo base (~369 MB)
./scripts/bundle.sh release   # compila e empacota o Sombra.app (modelo embutido)
open ./build/Sombra.app
```

Conceda a **Acessibilidade** (Ajustes do Sistema → Privacidade e Segurança →
Acessibilidade → Sombra). É a única permissão necessária. Como o app é assinado
*ad-hoc*, ao atualizar o binário pode ser preciso reconceder.

### Arquitetura

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
| Preferências/GUI | `SombraSettings.swift`, `SettingsView.swift`, `SettingsWindowController.swift` | Estado persistido + janela SwiftUI |
| Modelos | `ModelManager.swift`, `ModelCatalog.swift`, `ModelLocator.swift` | Baixar/importar/apagar/localizar `.gguf` |

```
digitação (thread do tap, não bloqueia)
   → ao PAUSAR (~70 ms) → AXReader lê janela do texto + posição + app
   → app bloqueado? descarta. senão:
   → Predictor.predict() em background (KV-cache reutiliza o prefixo)
   → tem continuação?  bubble (autocomplete)
       senão  última palavra errada?  bubble laranja (correção)
   → Tab → consome → TextInjector insere a palavra (ou substitui na correção)
```

### Por que llama.cpp (e não MLX)?

O MLX exige o compilador Metal do **Xcode completo** em tempo de build. O
llama.cpp compila os shaders Metal em **runtime** (`GGML_METAL_EMBED_LIBRARY`),
então roda só com o Command Line Tools — e entrega a mesma velocidade em modelos
pequenos no Apple Silicon. Reaproveita o **KV-cache** entre teclas (decodifica só
os tokens novos), o que mantém a latência baixa em textos longos.

### ☕ Apoie

Se a Sombra for útil pra você e quiser apoiar — totalmente opcional:

- ☕ **Ko-fi:** https://ko-fi.com/andre38264
- 💳 **PayPal:** https://www.paypal.com/donate/?business=FF3HTRZWDV8HS&no_recurring=0&item_name=Hey+you+%3AD&currency_code=EUR
- 🇧🇷 **Pix:** `37adbd1c-6e5e-4d2f-916a-04bc892fe496`

### Roadmap

- [x] Correção ortográfica da última palavra (NSSpellChecker, multilíngue)
- [x] Avaliação orientada a evento (sem polling pesado na main thread)
- [x] Bloquear apps + prompts por app
- [x] KV-cache reuse entre teclas
- [x] Preferências persistidas + GUI
- [ ] Modo corretor gramatical de frase (via chat template)
- [ ] Acompanhar fonte/tamanho do app alvo na sombra
- [ ] Teardown limpo do Metal ao sair

## License / Licença

MIT — see [LICENSE](LICENSE). © 2026 André Luís Alves Campos.
