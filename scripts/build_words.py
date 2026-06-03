#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Constrói Resources/words.bin — o DICIONÁRIO DE PALAVRAS EMBUTIDO, ranqueado por
FREQUÊNCIA (PT-BR + EN + DE), usado pela Sombra para COMPLETAÇÃO instantânea
(sem GPU). Complementa o NSSpellChecker: cobre nomes próprios, termos técnicos e
gírias que hoje caem no LLM, e ordena por frequência (melhor sugestão primeiro).

Fonte: o pacote `wordfreq` (dados embutidos no próprio pacote → roda OFFLINE
depois de instalado; junta subtítulos, Wikipédia, notícias, web). Licença
permissiva. Build é OFFLINE/única — o resultado (words.bin) é que vai no app.

Instalar e rodar (venv recomendado; build/ é gitignored):
    python3 -m venv build/words-venv
    build/words-venv/bin/pip install wordfreq
    build/words-venv/bin/python scripts/build_words.py

Ajustes por env:
    SOMBRA_WORDS_N=60000     # padrão por idioma (override global)
    SOMBRA_WORDS_T=32        # limiar de range p/ pré-computar o top-k (V2)
    SOMBRA_WORDS_K=16        # quantos completions pré-computar por prefixo
    SOMBRA_WORDS_OUT=path    # padrão Resources/words.bin

============================ FORMATO "SWD2" (V2) ============================
Little-endian. DEVE casar com WordDictionary.swift.

A novidade do V2 é a TABELA DE COMPLETAÇÃO PRÉ-COMPUTADA: para os prefixos com
muitos completions (range > T) — que no V1 exigiam varrer milhares de palavras —
o top-k por frequência já vem pronto. Consulta vira binária + leitura (O(prefixo)
em vez de O(range)). Prefixos de range pequeno NÃO entram na tabela (a varredura
do V1 já é instantânea neles). Resultado idêntico ao V1, só mais rápido.

    Cabeçalho:
        magic     : 4 bytes  b"SWD2"
        u32       : langCount
        u32       : K               # top-k por prefixo pré-computado
    Tabela de idiomas (langCount * 20 bytes):
        4s  langCode  (ascii, null-padded: b"pt\\0\\0")
        u32 count                   # nº de palavras
        u32 wordOffset              # offset do bloco de palavras
        u32 tblCount                # nº de prefixos pré-computados
        u32 tblOffset               # offset do bloco da tabela
    Bloco de palavras (em wordOffset):
        u32 count
        u32 freq[count]             # peso por frequência (maior = mais frequente)
        u32 off[count+1]            # offsets em `strings` (off[0]=0 .. off[count]=len)
        u8  strings[...]            # palavras minúsculas UTF-8 concatenadas,
                                    # ORDENADAS pelos BYTES UTF-8 (busca binária)
    Bloco da tabela (em tblOffset):
        u32 tblCount
        u32 poff[tblCount+1]        # offsets em `prefixes`
        u8  prefixes[...]           # prefixos (UTF-8) ORDENADOS por bytes
        u32 topk[tblCount*K]        # por prefixo, K índices na palavra (ordem de
                                    # frequência desc); 0xFFFFFFFF = vazio (padding)
"""

import os
import struct
import sys
import bisect

DEFAULT_N = int(os.environ.get("SOMBRA_WORDS_N", "0") or "0")
LANGS = [
    ("pt", DEFAULT_N or 60000),
    ("en", DEFAULT_N or 80000),
    ("de", DEFAULT_N or 40000),
]
# V2: pré-computa o top-k só para prefixos com range > T (os caros). Os demais
# (a grande maioria, range ~1-2) ficam para a varredura instantânea do V1.
T_RANGE = int(os.environ.get("SOMBRA_WORDS_T", "32"))
TOPK = int(os.environ.get("SOMBRA_WORDS_K", "16"))
LCAP = 20  # comprimento máx. de prefixo considerado (acima disso o range é ~0)
EMPTY = 0xFFFFFFFF

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("SOMBRA_WORDS_OUT", os.path.join(ROOT, "Resources", "words.bin"))


def normalize(w):
    """Minúscula, normaliza apóstrofo, apara apóstrofos/hífens das pontas."""
    return w.replace("’", "'").lower().strip("'-")


def keep(w):
    """Mantém palavras de letras (+ apóstrofo/hífen internos), sem dígitos, 2+ chars."""
    if len(w) < 2:
        return False
    if any(ch.isdigit() for ch in w):
        return False
    if not all(ch.isalpha() or ch in "'-" for ch in w):
        return False
    return any(ch.isalpha() for ch in w)


def build_block(lang, n, top_n_list):
    """Devolve (count, word_block, tbl_count, tbl_block) para um idioma."""
    raw = top_n_list(lang, n, wordlist="large")
    # Filtra preservando a ORDEM de frequência (top_n_list já vem ordenado).
    seen = {}
    for w in raw:
        nw = normalize(w)
        if keep(nw) and nw not in seen:
            seen[nw] = len(seen)  # rank (0 = mais frequente)
    if not seen:
        return 0, b"", 0, b""

    total = len(seen)
    # Peso por frequência: maior = mais frequente (preserva a ordem exata).
    weight = {w: total - rank for w, rank in seen.items()}
    # Ordena pelos BYTES UTF-8 (a busca binária em Swift compara bytes crus).
    words = sorted(seen.keys(), key=lambda s: s.encode("utf-8"))
    wb = [w.encode("utf-8") for w in words]   # bytes, na mesma ordem
    wt = [weight[w] for w in words]           # peso, na mesma ordem (por índice)

    # --- bloco de palavras ---
    freqs = bytearray()
    offs = bytearray()
    strings = bytearray()
    off = 0
    for i in range(total):
        offs += struct.pack("<I", off)
        strings += wb[i]
        off += len(wb[i])
        freqs += struct.pack("<I", wt[i])
    offs += struct.pack("<I", off)  # sentinela final
    word_block = struct.pack("<I", total) + bytes(freqs) + bytes(offs) + bytes(strings)

    # --- tabela de top-k pré-computado (prefixos de range grande) ---
    # Conta quantas palavras têm cada prefixo (alinhado a CARACTERE → o prefixo
    # nunca corta um caractere multibyte no meio; o usuário sempre digita
    # prefixos alinhados a caractere).
    pref = {}
    for w in words:
        m = min(len(w), LCAP)
        for L in range(1, m + 1):
            key = w[:L].encode("utf-8")
            pref[key] = pref.get(key, 0) + 1
    big = sorted(p for p, c in pref.items() if c > T_RANGE)  # ordenados por bytes

    poff = bytearray()
    pstr = bytearray()
    topk = bytearray()
    pacc = 0
    for p in big:
        lo = bisect.bisect_left(wb, p)        # 1ª palavra >= p (bytes)
        cand = []
        i = lo
        plen = len(p)
        while i < total and wb[i][:plen] == p:
            if len(wb[i]) > plen:             # extensão estrita
                cand.append((wt[i], i))
            i += 1
        cand.sort(key=lambda x: -x[0])        # frequência desc
        idxs = [i for _, i in cand[:TOPK]]
        while len(idxs) < TOPK:               # padding (não deve ocorrer: range>T>=K)
            idxs.append(EMPTY)
        poff += struct.pack("<I", pacc)
        pstr += p
        pacc += plen
        for ix in idxs:
            topk += struct.pack("<I", ix)
    poff += struct.pack("<I", pacc)           # sentinela final
    tbl_count = len(big)
    tbl_block = struct.pack("<I", tbl_count) + bytes(poff) + bytes(pstr) + bytes(topk)

    # Auto-checagem: a tabela DEVE bater com a força-bruta para alguns prefixos.
    _self_check(wb, wt, total, big, tbl_block, lang)

    return total, word_block, tbl_count, tbl_block


def _self_check(wb, wt, total, big, tbl_block, lang):
    """Confere que o top-k pré-computado == varredura força-bruta (amostra)."""
    if not big:
        return
    tbl_count = struct.unpack_from("<I", tbl_block, 0)[0]
    poff_base = 4
    pstr_base = poff_base + 4 * (tbl_count + 1)
    pstr_len = struct.unpack_from("<I", tbl_block, poff_base + 4 * tbl_count)[0]
    topk_base = pstr_base + pstr_len
    sample = big[:: max(1, len(big) // 50)]   # ~50 prefixos
    for p in sample:
        ti = big.index(p)
        a = struct.unpack_from("<I", tbl_block, poff_base + 4 * ti)[0]
        b = struct.unpack_from("<I", tbl_block, poff_base + 4 * (ti + 1))[0]
        assert tbl_block[pstr_base + a:pstr_base + b] == p
        stored = []
        for j in range(TOPK):
            ix = struct.unpack_from("<I", tbl_block, topk_base + 4 * (ti * TOPK + j))[0]
            if ix == EMPTY:
                break
            stored.append(ix)
        lo = bisect.bisect_left(wb, p)
        cand = []
        i = lo
        while i < total and wb[i][:len(p)] == p:
            if len(wb[i]) > len(p):
                cand.append((wt[i], i))
            i += 1
        cand.sort(key=lambda x: -x[0])
        brute = [i for _, i in cand[:TOPK]]
        assert stored == brute, f"[{lang}] mismatch em {p!r}"


def main():
    try:
        from wordfreq import top_n_list
    except ImportError:
        sys.stderr.write(
            "ERRO: pacote `wordfreq` não encontrado.\n"
            "  python3 -m venv build/words-venv\n"
            "  build/words-venv/bin/pip install wordfreq\n"
            "  build/words-venv/bin/python scripts/build_words.py\n"
        )
        sys.exit(1)

    blocks = []
    for lang, n in LANGS:
        count, wblk, tcount, tblk = build_block(lang, n, top_n_list)
        blocks.append((lang, count, wblk, tcount, tblk))
        print(f"  {lang}: {count:>7} palavras | tabela: {tcount:>5} prefixos "
              f"({(len(wblk)+len(tblk))/1024:.0f} KB)")

    lang_count = len(blocks)
    header = b"SWD2" + struct.pack("<II", lang_count, TOPK)
    header_len = len(header) + lang_count * 20   # 20 bytes por entrada

    table = bytearray()
    body = bytearray()
    offset = header_len
    for lang, count, wblk, tcount, tblk in blocks:
        word_off = offset
        body += wblk
        offset += len(wblk)
        tbl_off = offset
        body += tblk
        offset += len(tblk)
        code = lang.encode("ascii")[:4].ljust(4, b"\x00")
        table += struct.pack("<4sIIII", code, count, word_off, tcount, tbl_off)

    out = bytes(header) + bytes(table) + bytes(body)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(out)

    print(f"==> {OUT}")
    print(f"    total: {len(out)/1024/1024:.2f} MB  ({lang_count} idiomas, "
          f"top-{TOPK} pré-computado p/ range>{T_RANGE})")


if __name__ == "__main__":
    main()
