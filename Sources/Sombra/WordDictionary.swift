import Foundation

/// Dicionário de palavras EMBUTIDO, ranqueado por FREQUÊNCIA (PT/EN/DE), para
/// COMPLETAÇÃO instantânea — em microssegundos, SEM GPU. Complementa o
/// NSSpellChecker: cobre nomes próprios, termos técnicos e gírias que hoje caem
/// no LLM (ex.: "kubern" → "kubernetes"), e ordena por frequência (melhor
/// sugestão primeiro = menos teclas). Diferente do NSSpellChecker, completa já a
/// partir de 1 letra.
///
/// **V2 (formato "SWD2"):** os prefixos de range grande (os caros — "co", "re"…)
/// têm o top-k por frequência PRÉ-COMPUTADO numa tabela. A consulta vira uma
/// busca binária na tabela + leitura (O(prefixo)), em vez de varrer milhares de
/// palavras. Prefixos de range pequeno caem na varredura do V1 (já instantânea).
/// O resultado é IDÊNTICO ao V1 — só mais rápido.
///
/// Dado em Resources/words.bin, gerado offline por scripts/build_words.py
/// (layout completo documentado lá). Carregado uma vez (imutável depois) → seguro
/// para ler de qualquer thread.
enum WordDictionary {
    /// Descritor de um idioma: offsets (em bytes, dentro de `bytes`) das seções.
    private struct Block {
        // Bloco de palavras (V1).
        let count: Int      // nº de palavras
        let freqBase: Int   // freq[count]    (u32 cada)
        let offBase: Int    // off[count+1]   (u32 cada)
        let strBase: Int    // strings (UTF-8 concatenado, ordenado por bytes)
        // Tabela de top-k pré-computado (V2).
        let tblCount: Int   // nº de prefixos pré-computados
        let poffBase: Int   // poff[tblCount+1] (offsets dos prefixos)
        let pstrBase: Int   // prefixos (UTF-8, ordenados por bytes)
        let topkBase: Int   // topk[tblCount*topK] (índices na palavra, freq desc)
        let topK: Int       // K por prefixo (do cabeçalho)
    }

    /// Completações (palavras inteiras) que ESTENDEM `partial` no `language`
    /// dado, ranqueadas por frequência (maior primeiro), até `limit`. Vazio se o
    /// idioma não está no dicionário, o arquivo não carregou, ou não há match.
    /// Só devolve extensões ESTRITAS (palavra mais longa que o digitado).
    static func completions(forPartial partial: String, language: String, limit: Int = 12) -> [String] {
        guard let code = langCode(language), let blk = blocks[code] else { return [] }
        let p = Array(partial.lowercased().utf8)
        guard !p.isEmpty else { return [] }

        // V2 — caminho rápido: prefixo pré-computado? Busca binária na tabela e lê
        // o top-k pronto. Sem varrer range nenhum.
        if blk.tblCount > 0, let ti = tableIndex(p, blk) {
            var out: [String] = []
            let base = blk.topkBase + 4 * blk.topK * ti
            for j in 0..<blk.topK {
                let idx = readU32(base + 4 * j)
                if idx == 0xFFFF_FFFF { break }     // padding (não ocorre p/ range>T)
                out.append(decodeWord(Int(idx), blk))
                if out.count >= limit { break }
            }
            return out
        }

        // V1 — varredura: as palavras com o prefixo `p` formam um intervalo
        // contíguo (estão ordenadas por bytes). Quando NÃO está na tabela, esse
        // intervalo é pequeno (range <= T), então varrer é instantâneo.
        var matches: [(freq: UInt32, idx: Int)] = []
        var i = lowerBound(p, blk)
        while i < blk.count {
            let (s, e) = wordRange(i, blk)
            if !hasPrefix(s, e, p) { break }
            if e - s > p.count {                    // extensão estrita
                matches.append((readU32(blk.freqBase + 4 * i), i))
            }
            i += 1
        }
        guard !matches.isEmpty else { return [] }
        matches.sort { $0.freq > $1.freq }          // mais frequente primeiro
        return matches.prefix(limit).map { decodeWord($0.idx, blk) }
    }

    /// O dicionário carregou com sucesso? (para diagnóstico / CLI de teste).
    static var isLoaded: Bool { !blocks.isEmpty }

    /// Resumo legível dos idiomas carregados (para a CLI de teste).
    static var info: String {
        guard isLoaded else { return "WordDictionary: NÃO carregado (words.bin não encontrado)" }
        let parts = blocks.keys.sorted().map { "\($0)=\(blocks[$0]!.count)(tbl \(blocks[$0]!.tblCount))" }
        return "WordDictionary[SWD2]: \(bytes.count) bytes, " + parts.joined(separator: " ")
    }

    // MARK: - Busca

    private static func langCode(_ language: String) -> String? {
        let l = language.lowercased()
        if l.hasPrefix("pt") { return "pt" }
        if l.hasPrefix("en") { return "en" }
        if l.hasPrefix("de") { return "de" }
        return nil
    }

    /// Índice do prefixo `p` na tabela pré-computada (match EXATO), ou nil.
    private static func tableIndex(_ p: [UInt8], _ blk: Block) -> Int? {
        var lo = 0, hi = blk.tblCount
        while lo < hi {
            let mid = (lo + hi) / 2
            let (s, e) = prefixRange(mid, blk)
            switch compareBytes(s, e, p) {
            case .orderedAscending: lo = mid + 1
            case .orderedDescending: hi = mid
            case .orderedSame: return mid
            }
        }
        return nil
    }

    /// Faixa de bytes [start,end) do prefixo `idx` da tabela, dentro de `bytes`.
    private static func prefixRange(_ idx: Int, _ blk: Block) -> (Int, Int) {
        let a = Int(readU32(blk.poffBase + 4 * idx))
        let b = Int(readU32(blk.poffBase + 4 * (idx + 1)))
        return (blk.pstrBase + a, blk.pstrBase + b)
    }

    /// Compara os bytes em [start,end) com `p` (lexicográfico).
    private static func compareBytes(_ start: Int, _ end: Int, _ p: [UInt8]) -> ComparisonResult {
        var i = start, j = 0
        while i < end && j < p.count {
            let a = bytes[i], b = p[j]
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
            i += 1; j += 1
        }
        let lw = end - i, lp = p.count - j
        if lw == lp { return .orderedSame }
        return lw < lp ? .orderedAscending : .orderedDescending
    }

    /// Menor índice cuja palavra é >= `p` (comparação por bytes UTF-8).
    private static func lowerBound(_ p: [UInt8], _ blk: Block) -> Int {
        var lo = 0, hi = blk.count
        while lo < hi {
            let mid = (lo + hi) / 2
            let (s, e) = wordRange(mid, blk)
            if compareBytes(s, e, p) == .orderedAscending { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// A palavra em [start,end) começa com `p`?
    private static func hasPrefix(_ start: Int, _ end: Int, _ p: [UInt8]) -> Bool {
        guard end - start >= p.count else { return false }
        var i = start
        for b in p {
            if bytes[i] != b { return false }
            i += 1
        }
        return true
    }

    /// Faixa de bytes [start,end) da palavra `idx` dentro de `bytes`.
    private static func wordRange(_ idx: Int, _ blk: Block) -> (Int, Int) {
        let a = Int(readU32(blk.offBase + 4 * idx))
        let b = Int(readU32(blk.offBase + 4 * (idx + 1)))
        return (blk.strBase + a, blk.strBase + b)
    }

    private static func decodeWord(_ idx: Int, _ blk: Block) -> String {
        let (s, e) = wordRange(idx, blk)
        return String(decoding: bytes[s..<e], as: UTF8.self)
    }

    /// Lê um u32 little-endian em `o` (sem exigir alinhamento).
    private static func readU32(_ o: Int) -> UInt32 {
        UInt32(bytes[o]) | (UInt32(bytes[o + 1]) << 8)
            | (UInt32(bytes[o + 2]) << 16) | (UInt32(bytes[o + 3]) << 24)
    }

    // MARK: - Carga (uma vez, imutável)

    private static let bytes: [UInt8] = loadBytes()
    private static let blocks: [String: Block] = parse()

    private static func loadBytes() -> [UInt8] {
        // 1) Dentro do .app (Contents/Resources/words.bin, copiado por bundle.sh).
        if let url = Bundle.main.url(forResource: "words", withExtension: "bin"),
           let d = try? Data(contentsOf: url) { return [UInt8](d) }
        // 2) Override por env (selftest/CLI: SOMBRA_WORDS=/caminho/words.bin).
        if let p = ProcessInfo.processInfo.environment["SOMBRA_WORDS"], !p.isEmpty,
           let d = try? Data(contentsOf: URL(fileURLWithPath: p)) { return [UInt8](d) }
        // 3) Dev: sobe a árvore procurando Resources/words.bin (igual ao ModelLocator).
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        var dir: URL? = exe.deletingLastPathComponent()
        for _ in 0..<10 {
            guard let d = dir else { break }
            let cand = d.appendingPathComponent("Resources").appendingPathComponent("words.bin")
            if let data = try? Data(contentsOf: cand) { return [UInt8](data) }
            dir = d.deletingLastPathComponent()
        }
        return []
    }

    /// Parseia o cabeçalho "SWD2" + a tabela de idiomas em descritores `Block`.
    private static func parse() -> [String: Block] {
        let b = bytes
        // magic "SWD2"
        guard b.count >= 12, b[0] == 0x53, b[1] == 0x57, b[2] == 0x44, b[3] == 0x32 else { return [:] }
        let langCount = Int(readU32(4))
        let topK = Int(readU32(8))
        guard topK > 0 else { return [:] }
        var result: [String: Block] = [:]
        var o = 12
        for _ in 0..<langCount {
            guard o + 20 <= b.count else { break }
            var codeBytes: [UInt8] = []
            for k in 0..<4 where b[o + k] != 0 { codeBytes.append(b[o + k]) }
            let code = String(decoding: codeBytes, as: UTF8.self)
            let count = Int(readU32(o + 4))
            let wordOff = Int(readU32(o + 8))
            let tblCount = Int(readU32(o + 12))
            let tblOff = Int(readU32(o + 16))
            o += 20
            // Bloco de palavras: u32 count | freq[count] | off[count+1] | strings
            let freqBase = wordOff + 4
            let offBase = freqBase + 4 * count
            let strBase = offBase + 4 * (count + 1)
            // Bloco da tabela: u32 tblCount | poff[tblCount+1] | prefixos | topk[tblCount*K]
            let poffBase = tblOff + 4
            let pstrBase = poffBase + 4 * (tblCount + 1)
            guard count > 0, strBase <= b.count,
                  tblCount == 0 || poffBase + 4 * (tblCount + 1) <= b.count else { continue }
            let pstrLen = tblCount > 0 ? Int(readU32(poffBase + 4 * tblCount)) : 0
            let topkBase = pstrBase + pstrLen
            guard topkBase + 4 * tblCount * topK <= b.count else { continue }
            result[code] = Block(count: count, freqBase: freqBase, offBase: offBase, strBase: strBase,
                                 tblCount: tblCount, poffBase: poffBase, pstrBase: pstrBase,
                                 topkBase: topkBase, topK: topK)
        }
        return result
    }
}
