import Foundation

/// Catálogo de emojis para o atalho ":nome" (estilo Slack/GitHub). Usa os nomes
/// PADRÃO (dataset gemoji embutido em Resources/emoji.json): `:fire:`, `:joy:`,
/// `:fireworks:`, `:rocket:`… — consistentes e completos. Resolve gênero e tom de
/// pele para emojis de pessoa/mão. Tudo local, instantâneo, sem o modelo de IA.
enum EmojiCatalog {
    private struct Item: Decodable {
        let e: String       // o emoji
        let a: [String]     // aliases (nomes canônicos :assim:)
        let t: [String]     // tags (sinônimos de busca)
        let s: Bool         // aceita modificador de tom de pele
    }

    /// Emoji para uma consulta (minúscula), aplicando gênero/tom de pele.
    /// Prioridade: alias inglês exato > tag exata > apelido localizado (PT/DE)
    /// exato > prefixo de alias > prefixo de tag > prefixo de apelido localizado.
    /// Os apelidos PT/DE mapeiam para o alias inglês canônico (ex.: "festa"/"feier"
    /// -> tada 🎉, "fogo"/"feuer" -> fire 🔥).
    @MainActor
    static func emoji(forQuery q: String) -> String? {
        guard !items.isEmpty else { return nil }
        if let i = aliasExact[q] ?? tagExact[q] { return resolve(items[i]) }
        if let i = localeExact(q) { return resolve(items[i]) }
        if let i = bestPrefix(q) { return resolve(items[i]) }
        if let i = localePrefix(q) { return resolve(items[i]) }
        return nil
    }

    // Apelidos localizados (PT + DE), sem acento. Resolvem para o alias inglês.
    private static let localeMaps: [[String: String]] = [ptAliases, deAliases]

    private static func localeExact(_ q: String) -> Int? {
        let f = fold(q)
        for map in localeMaps {
            if let en = map[f], let i = aliasExact[en] ?? tagExact[en] { return i }
        }
        return nil
    }
    private static func localePrefix(_ q: String) -> Int? {
        let fq = fold(q)
        guard fq.count >= 2 else { return nil }
        var best: (alias: String, len: Int)?
        for map in localeMaps {
            for (k, en) in map where k.hasPrefix(fq) {
                if best == nil || k.count < best!.len { best = (en, k.count) }
            }
        }
        guard let en = best?.alias else { return nil }
        return aliasExact[en] ?? tagExact[en]
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
    }

    private static func bestPrefix(_ q: String) -> Int? {
        func search(_ names: (Item) -> [String]) -> Int? {
            var best: (idx: Int, len: Int)?
            for (i, it) in items.enumerated() {
                for n in names(it) where n.hasPrefix(q) {
                    if best == nil || n.count < best!.len
                        || (n.count == best!.len && i < best!.idx) {
                        best = (i, n.count)
                    }
                }
            }
            return best?.idx
        }
        return search(\.a) ?? search(\.t)   // aliases têm prioridade sobre tags
    }

    @MainActor
    private static func resolve(_ item: Item) -> String {
        var base = item.e
        let g = SombraSettings.shared.emojiGender
        if g != 0, let pair = genderMap[item.e] {
            base = (g == 1) ? pair.f : pair.m
        }
        if item.s, let tone = skinToneScalar(SombraSettings.shared.emojiSkinTone) {
            base = applyTone(base, tone)
        }
        return base
    }

    private static func skinToneScalar(_ idx: Int) -> Unicode.Scalar? {
        switch idx {
        case 1: return "\u{1F3FB}"; case 2: return "\u{1F3FC}"; case 3: return "\u{1F3FD}"
        case 4: return "\u{1F3FE}"; case 5: return "\u{1F3FF}"; default: return nil
        }
    }

    /// Insere o modificador de tom após o 1º scalar (o emoji-base humano),
    /// descartando um seletor de variação (U+FE0F) que o tom substitui. Funciona
    /// para emojis simples (👍 -> 👍🏽) e para sequências ZWJ (🤷‍♀️ -> 🤷🏽‍♀️).
    private static func applyTone(_ emoji: String, _ tone: Unicode.Scalar) -> String {
        var s = Array(emoji.unicodeScalars)
        guard !s.isEmpty else { return emoji }
        if s.count > 1, s[1] == "\u{FE0F}" { s.remove(at: 1) }
        s.insert(tone, at: 1)
        return String(String.UnicodeScalarView(s))
    }

    /// Apelidos em português (sem acento) -> alias inglês canônico do gemoji.
    /// Permite digitar `:festa`, `:fogo`, `:coracao`… além dos nomes em inglês.
    private static let ptAliases: [String: String] = [
        "festa": "tada", "comemorar": "tada", "parabens": "tada", "confete": "confetti_ball",
        "festarosto": "partying_face", "coracao": "heart", "amor": "heart",
        "fogo": "fire", "bombando": "fire", "foguete": "rocket", "decolar": "rocket",
        "joinha": "+1", "curtir": "+1", "positivo": "+1", "descurtir": "-1", "negativo": "-1",
        "palmas": "clap", "aplausos": "clap", "riso": "joy", "rindo": "joy", "kkk": "joy",
        "chorando": "sob", "choro": "cry", "triste": "cry", "bravo": "angry", "raiva": "rage",
        "feliz": "smile", "alegre": "smile", "apaixonado": "heart_eyes", "beijo": "kissing_heart",
        "pensando": "thinking", "duvida": "thinking", "oculos": "sunglasses", "estiloso": "sunglasses",
        "caveira": "skull", "morte": "skull", "fantasma": "ghost", "robo": "robot", "coco": "poop",
        "cafe": "coffee", "cerveja": "beer", "bolo": "birthday", "presente": "gift",
        "dinheiro": "moneybag", "grana": "moneybag", "estrela": "star", "raio": "zap", "energia": "zap",
        "certo": "white_check_mark", "correto": "white_check_mark", "feito": "white_check_mark",
        "errado": "x", "errou": "x", "aviso": "warning", "atencao": "warning", "pergunta": "question",
        "ideia": "bulb", "lampada": "bulb", "alvo": "dart", "meta": "dart", "trofeu": "trophy",
        "campeao": "trophy", "medalha": "1st_place_medal", "musica": "musical_note",
        "foto": "camera", "video": "movie_camera", "chave": "key", "cadeado": "lock",
        "lixo": "wastebasket", "relogio": "alarm_clock", "livro": "books", "sol": "sunny",
        "lua": "crescent_moon", "chuva": "cloud_with_rain", "neve": "snowflake",
        "arvore": "deciduous_tree", "flor": "cherry_blossom", "arcoiris": "rainbow",
        "cachorro": "dog", "gato": "cat", "unicornio": "unicorn", "cobra": "snake", "leao": "lion",
        "reza": "pray", "rezar": "pray", "obrigado": "pray", "porfavor": "pray", "forca": "muscle",
        "musculo": "muscle", "academia": "muscle", "aceno": "wave", "tchau": "wave", "ola": "wave",
        "joia": "ok_hand", "programador": "technologist", "programadora": "technologist",
        // extras
        "fogos": "fireworks", "fogosdeartificio": "fireworks", "comida": "pizza",
        "hamburguer": "hamburger", "bebida": "beer", "vinho": "wine_glass",
        "carro": "car", "aviao": "airplane", "casa": "house", "trabalho": "briefcase",
        "computador": "computer", "telefone": "telephone", "celular": "iphone",
        "email": "email", "mensagem": "speech_balloon", "sino": "bell", "alarme": "alarm_clock",
        "calendario": "calendar", "anotacao": "memo", "lapis": "pencil2", "caneta": "pen",
        "cerebro": "brain", "olhos": "eyes", "olhar": "eyes", "piscar": "wink",
        "abraco": "hugs", "suor": "sweat_smile", "sono": "sleeping", "dormindo": "sleeping",
        "medo": "scream", "assustado": "scream", "nojo": "nauseated_face", "vomito": "nauseated_face",
        "anjo": "innocent", "diabo": "smiling_imp", "palhaco": "clown_face", "alien": "alien",
        "cem": "100", "nota": "musical_note", "sol": "sunny", "guardachuva": "umbrella",
        "boneco": "snowman", "arvorenatal": "christmas_tree", "natal": "christmas_tree",
        "maos": "raised_hands", "louvor": "raised_hands", "soco": "punch", "punho": "fist",
        "ok": "ok_hand", "estrelinha": "star2", "brilho": "sparkles", "magia": "sparkles",
        "gato": "cat", "cachorro": "dog", "peixe": "fish", "passaro": "bird", "flor": "cherry_blossom",
    ]

    /// Apelidos em alemão (sem acento) -> alias inglês canônico do gemoji.
    /// Permite digitar `:feuer`, `:herz`, `:danke`… além dos nomes em inglês.
    private static let deAliases: [String: String] = [
        "feuer": "fire", "rakete": "rocket", "herz": "heart", "liebe": "heart",
        "feuerwerk": "fireworks", "party": "tada", "feier": "tada", "feiern": "tada",
        "daumenhoch": "+1", "daumenrunter": "-1", "klatschen": "clap", "applaus": "clap",
        "lachen": "joy", "weinen": "sob", "traurig": "cry", "wuetend": "rage", "boese": "angry",
        "gluecklich": "smile", "freude": "smile", "froh": "smile", "kuss": "kissing_heart",
        "denken": "thinking", "nachdenken": "thinking", "sonnenbrille": "sunglasses",
        "totenkopf": "skull", "geist": "ghost", "roboter": "robot", "kacke": "poop",
        "kaffee": "coffee", "bier": "beer", "wein": "wine_glass", "kuchen": "birthday",
        "geschenk": "gift", "geld": "moneybag", "stern": "star", "blitz": "zap",
        "richtig": "white_check_mark", "fertig": "white_check_mark", "falsch": "x",
        "achtung": "warning", "warnung": "warning", "frage": "question", "idee": "bulb",
        "ziel": "dart", "pokal": "trophy", "medaille": "1st_place_medal", "musik": "musical_note",
        "foto": "camera", "video": "movie_camera", "schluessel": "key", "schloss": "lock",
        "muell": "wastebasket", "uhr": "alarm_clock", "buch": "books", "sonne": "sunny",
        "mond": "crescent_moon", "regen": "cloud_with_rain", "schnee": "snowflake",
        "baum": "deciduous_tree", "blume": "cherry_blossom", "regenbogen": "rainbow",
        "hund": "dog", "katze": "cat", "schlange": "snake", "loewe": "lion",
        "beten": "pray", "danke": "pray", "bitte": "pray", "muskel": "muscle",
        "winken": "wave", "tschuess": "wave", "hallo": "wave", "programmierer": "technologist",
        "computer": "computer", "telefon": "telephone", "handy": "iphone", "auto": "car",
        "gehirn": "brain", "augen": "eyes", "zwinkern": "wink", "umarmung": "hugs",
        "schlafen": "sleeping", "angst": "scream", "engel": "innocent", "gehirnschmalz": "brain",
        "haus": "house", "essen": "pizza", "glocke": "bell", "schneemann": "snowman",
    ]

    /// Variantes de gênero para os emojis de pessoa mais comuns (chave = emoji
    /// neutro). Os demais usam o nome explícito do padrão (`:woman_x:` etc.).
    private static let genderMap: [String: (f: String, m: String)] = [
        "🤷": ("🤷‍♀️", "🤷‍♂️"), "🤦": ("🤦‍♀️", "🤦‍♂️"),
        "🙋": ("🙋‍♀️", "🙋‍♂️"), "🙅": ("🙅‍♀️", "🙅‍♂️"),
        "🙆": ("🙆‍♀️", "🙆‍♂️"), "🙇": ("🙇‍♀️", "🙇‍♂️"),
        "💁": ("💁‍♀️", "💁‍♂️"), "🏃": ("🏃‍♀️", "🏃‍♂️"),
        "🚶": ("🚶‍♀️", "🚶‍♂️"), "🧑": ("👩", "👨"),
        "🧒": ("👧", "👦"), "🧓": ("👵", "👴"),
        "🧑‍💻": ("👩‍💻", "👨‍💻"), "🧑‍🏫": ("👩‍🏫", "👨‍🏫"),
        "🧑‍🍳": ("👩‍🍳", "👨‍🍳"), "🧑‍🎓": ("👩‍🎓", "👨‍🎓"),
        "🙎": ("🙎‍♀️", "🙎‍♂️"), "🙍": ("🙍‍♀️", "🙍‍♂️"),
    ]

    // Dataset padrão carregado uma vez (Resources/emoji.json, ~1870 emojis).
    private static let items: [Item] = {
        guard let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return arr
    }()
    private static let aliasExact: [String: Int] = {
        var m = [String: Int]()
        for (i, it) in items.enumerated() { for n in it.a where m[n] == nil { m[n] = i } }
        return m
    }()
    private static let tagExact: [String: Int] = {
        var m = [String: Int]()
        for (i, it) in items.enumerated() { for n in it.t where m[n] == nil { m[n] = i } }
        return m
    }()
}
